import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/market.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';
import '../widgets/panels.dart';
import '../widgets/stock_tile.dart';
import '../widgets/ticker_avatar.dart';
import '../widgets/watchlist_star.dart';
import 'stock_detail_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// One starred ticker and what the latest run still says about it.
class _Starred {
  const _Starred({
    required this.market,
    required this.ticker,
    required this.row,
    required this.window,
    required this.inSelectedWindow,
    required this.name,
  });

  final Market market;
  final String ticker;

  /// The published row, from [window]. Null when the run dropped the ticker
  /// from every window it publishes.
  final StockRow? row;
  final GrowthWindow? window;
  final bool inSelectedWindow;

  /// The company name, from the row or from the file's ticker directory.
  final String? name;

  String get key => '${market.id}:$ticker';

  int get _rank => inSelectedWindow ? 0 : (row != null ? 1 : 2);
}

/// Removes a ticker, with a way back: a swipe is easy to do by accident and
/// the list is the only record of what was on it.
void _unstar(BuildContext context, _Starred entry) {
  final watchlist = context.read<WatchlistController>();
  watchlist.remove(entry.market, entry.ticker);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('${entry.ticker} removed from the watchlist'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => watchlist.add(entry.market, entry.ticker),
        ),
      ),
    );
}

/// A starred row: the published tile where the run still lists it, and a
/// plain row saying so where it does not.
class _StarredTile extends StatelessWidget {
  const _StarredTile({
    required this.entry,
    required this.selected,
    required this.onSelect,
  });

  final _Starred entry;
  final bool selected;
  final ValueChanged<StockRow>? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = entry.row;

    if (row == null) {
      return ListTile(
        leading: TickerAvatar(ticker: entry.ticker),
        title: Text(
          entry.ticker,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          entry.name == null
              ? 'Dropped from the latest run'
              : '${entry.name} · dropped from the latest run',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: WatchlistStar(
          market: entry.market,
          ticker: entry.ticker,
          dense: true,
        ),
      );
    }

    final tile = StockTile(
      row: row,
      showMarketBadge: true,
      selected: selected,
      onTap: onSelect == null ? null : () => onSelect!(row),
      opensTo: onSelect != null
          ? null
          : (_) => StockDetailScreen(
              market: row.market,
              ticker: row.ticker,
              initialWindow: row.window,
            ),
    );

    if (entry.inSelectedWindow) return tile;

    // Listed, but not by the window the reader chose. Saying which one it
    // came from is the difference between a stale number and a labelled one.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.fromLTRB(66, 0, 16, 10),
          child: Text(
            'Not in the ${context.read<AppState>().selectedWindow.longLabel.toLowerCase()} '
            'screen — showing its ${entry.window!.longLabel.toLowerCase()} row',
            style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
          ),
        ),
      ],
    );
  }
}

/// Starred tickers from every market, with their current window figures.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key, this.onSelect, this.selected});

  /// See [MarketListScreen.onSelect]: set by the desktop shell, which shows
  /// the instrument beside the list rather than over it.
  final ValueChanged<StockRow>? onSelect;
  final StockRow? selected;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  /// The query in flight, kept across rebuilds.
  ///
  /// Building it inside [build] would re-read every file on every frame the
  /// screen is rebuilt for — a star, a snackbar, a theme change.
  Future<List<_Starred>>? _future;

  /// What [_future] was built from, so it is only rebuilt when it is stale.
  String? _inputs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = context.watch<AppState>();
    final watchlist = context.watch<WatchlistController>();
    final loaded = [
      for (final market in Market.values)
        if (appState.databaseOf(market) != null) market.id,
    ];
    final inputs =
        '${appState.selectedWindow.name}|${loaded.join(',')}|'
        '${watchlist.keys.join(',')}';
    if (inputs == _inputs) return;
    _inputs = inputs;
    _future = _load(appState, watchlist);
  }

  /// Every starred ticker, whether or not the selected window still lists it.
  ///
  /// A watchlist that quietly drops entries is not a watchlist. A ticker
  /// missing from the selected window is looked for in the others — the
  /// windows are threshold-filtered and a name that cleared the 1-year screen
  /// need not clear the 7-day one — and a ticker the run dropped entirely is
  /// still listed, by name, saying so.
  Future<List<_Starred>> _load(
    AppState appState,
    WatchlistController watchlist,
  ) async {
    final entries = <_Starred>[];

    for (final market in Market.values) {
      final database = appState.databaseOf(market);
      if (database == null) continue;
      final tickers = watchlist.tickersFor(market);
      if (tickers.isEmpty) continue;

      final windows = database.availableWindows;
      if (windows.isEmpty) continue;
      final selected = windows.contains(appState.selectedWindow)
          ? appState.selectedWindow
          : windows.first;

      final found = <String, (StockRow, GrowthWindow)>{};
      // The selected window first, so a ticker it lists is described by it.
      for (final window in [selected, ...windows.where((w) => w != selected)]) {
        final remaining = [
          for (final ticker in tickers)
            if (!found.containsKey(ticker)) ticker,
        ];
        if (remaining.isEmpty) break;
        for (final row in await database.stocks(
          window,
          StockQuery(tickers: remaining),
        )) {
          found[row.ticker] = (row, window);
        }
      }

      final names = found.length == tickers.length
          ? const <String, String>{}
          : await database.tickerNames();

      for (final ticker in tickers) {
        final hit = found[ticker];
        entries.add(
          _Starred(
            market: market,
            ticker: ticker,
            row: hit?.$1,
            window: hit?.$2,
            inSelectedWindow: hit?.$2 == selected,
            name: hit?.$1.shortName ?? names[ticker],
          ),
        );
      }
    }

    entries.sort((a, b) {
      // Listed in the selected window first, then found elsewhere, then the
      // ones the run dropped; strongest first within each group.
      final rank = a._rank.compareTo(b._rank);
      if (rank != 0) return rank;
      final left = a.row?.pctChange;
      final right = b.row?.pctChange;
      if (left == null || right == null) return a.ticker.compareTo(b.ticker);
      return right.compareTo(left);
    });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final watchlist = context.watch<WatchlistController>();
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist'),
        actions: [
          if (!watchlist.isEmpty)
            IconButton(
              tooltip: 'Clear watchlist',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => confirmClearWatchlist(context, watchlist),
            ),
          const InfoButton(info: PageInfos.watchlist),
          const SizedBox(width: 4),
        ],
      ),
      body: watchlist.isEmpty
          ? const StatusView(
              icon: Icons.star_border_rounded,
              title: 'No starred tickers yet',
              message:
                  'Open any stock and tap the star to keep an eye on it here.',
            )
          : FutureBuilder<List<_Starred>>(
              future: _future,
              builder: (context, snapshot) {
                // A future still in flight keeps the last one's data, so an
                // unstar has to be honoured here too — otherwise the row it
                // removed is rebuilt from the stale list, and a dismissed
                // `Dismissible` rebuilt is an error.
                final rows = [
                  for (final entry in snapshot.data ?? const <_Starred>[])
                    if (watchlist.contains(entry.market, entry.ticker)) entry,
                ];
                if (snapshot.data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final shown = rows
                    .where((entry) => entry.inSelectedWindow)
                    .length;
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text(
                        '$shown of ${watchlist.length} starred tickers '
                        'appear in the ${appState.selectedWindow.longLabel.toLowerCase()} window. '
                        'The rest are listed with what the run last said.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Panel(
                      child: Column(
                        children: [
                          for (final entry in rows) ...[
                            Dismissible(
                              key: ValueKey(entry.key),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: colors.negativeSurface,
                                child: Icon(
                                  Icons.star_border_rounded,
                                  color: colors.negative,
                                ),
                              ),
                              onDismissed: (_) => _unstar(context, entry),
                              child: _StarredTile(
                                entry: entry,
                                selected: entry.key == widget.selected?.key,
                                onSelect: widget.onSelect,
                              ),
                            ),
                            if (entry != rows.last)
                              Divider(
                                height: 1,
                                color: colors.divider,
                                indent: 66,
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
    );
  }
}
