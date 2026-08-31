import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/history_ticker.dart';
import '../../models/market.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/change_chip.dart';
import '../widgets/watchlist_highlight.dart';
import '../widgets/panels.dart';
import '../widgets/stock_tile.dart';
import '../widgets/ticker_avatar.dart';
import '../widgets/watchlist_star.dart';
import 'stock_detail_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// One instrument the published history carries that the selected screen does
/// not, and which screens — if any — it did clear this run.
class _HistoryHit {
  const _HistoryHit({
    required this.market,
    required this.ticker,
    required this.windows,
  });

  final Market market;
  final HistoryTicker ticker;

  /// Windows whose screen this ticker does appear in, shortest first. Empty
  /// when the run published no screen containing it.
  final List<GrowthWindow> windows;
}

/// A starred ticker the run has nothing to say about at all.
class _StarHit {
  const _StarHit({required this.market, required this.ticker, this.name});

  final Market market;
  final String ticker;
  final String? name;
}

/// A search, grouped by where the match was found.
class _Results {
  const _Results({
    required this.inScreen,
    required this.inHistory,
    required this.starred,
  });

  static const empty = _Results(inScreen: [], inHistory: [], starred: []);

  /// Rows the selected window publishes.
  final List<StockRow> inScreen;

  /// Instruments the file's price history covers, that this window does not.
  final List<_HistoryHit> inHistory;

  /// Starred tickers neither of the above found.
  final List<_StarHit> starred;

  bool get isEmpty => inScreen.isEmpty && inHistory.isEmpty && starred.isEmpty;
}

/// Search across every market at once.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _term = '';

  /// At most this many per market per group, so a two-letter term cannot
  /// build a list of the whole universe.
  static const _perMarket = 40;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _term = value.trim());
    });
  }

  /// Everything the term matches, in three groups.
  ///
  /// Searching only the selected window answers a narrower question than the
  /// one people ask: the screens are threshold-filtered, so a ticker the
  /// pipeline publishes a year of prices for is simply missing from search
  /// whenever this week's move was not big enough. The history is searched
  /// too, and a starred ticker the run dropped entirely is still findable.
  ///
  /// A ticker lands in the first group it qualifies for, so nothing is listed
  /// twice. That is why the third group is small: a starred ticker in the
  /// screen or the history is already shown there, wearing its star.
  Future<_Results> _search(
    AppState appState,
    WatchlistController watchlist,
  ) async {
    if (_term.isEmpty) return _Results.empty;
    final upper = _term.toUpperCase();

    final inScreen = <StockRow>[];
    final inHistory = <_HistoryHit>[];
    final starred = <_StarHit>[];

    for (final market in Market.values) {
      final database = appState.databaseOf(market);
      if (database == null) continue;
      final windows = database.availableWindows;
      if (windows.isEmpty) continue;
      final selected = windows.contains(appState.selectedWindow)
          ? appState.selectedWindow
          : windows.first;

      final rows = await database.stocks(
        selected,
        StockQuery(search: _term, limit: _perMarket),
      );
      inScreen.addAll(rows);
      final shown = {for (final row in rows) row.ticker};

      // Which other screens carry the term's matches, so a history hit can
      // say what it did clear rather than only what it missed.
      final elsewhere = <String, List<GrowthWindow>>{};
      for (final window in windows) {
        if (window == selected) continue;
        for (final row in await database.stocks(
          window,
          StockQuery(search: _term, limit: _perMarket),
        )) {
          (elsewhere[row.ticker] ??= []).add(window);
        }
      }

      for (final entry in await database.historyTickers()) {
        if (inHistory.length >= _perMarket * Market.values.length) break;
        if (shown.contains(entry.ticker)) continue;
        if (!_matches(entry.ticker, entry.name, upper)) continue;
        inHistory.add(
          _HistoryHit(
            market: market,
            ticker: entry,
            windows: elsewhere[entry.ticker] ?? const [],
          ),
        );
      }
      final found = {
        ...shown,
        for (final hit in inHistory)
          if (hit.market == market) hit.ticker.ticker,
      };

      final names = await database.tickerNames();
      for (final ticker in watchlist.tickersFor(market)) {
        if (found.contains(ticker)) continue;
        if (!_matches(ticker, names[ticker], upper)) continue;
        starred.add(
          _StarHit(market: market, ticker: ticker, name: names[ticker]),
        );
      }
    }

    // Exact ticker matches first, then by size of the move.
    inScreen.sort((a, b) {
      final rank = _exactness(a.ticker, upper) - _exactness(b.ticker, upper);
      if (rank != 0) return rank;
      return b.pctChange.compareTo(a.pctChange);
    });
    inHistory.sort((a, b) {
      final rank =
          _exactness(a.ticker.ticker, upper) -
          _exactness(b.ticker.ticker, upper);
      if (rank != 0) return rank;
      // A ticker that cleared some other screen is more interesting than one
      // that cleared none.
      if (a.windows.isEmpty != b.windows.isEmpty) {
        return a.windows.isEmpty ? 1 : -1;
      }
      return b.ticker.pctChange.compareTo(a.ticker.pctChange);
    });
    starred.sort((a, b) => a.ticker.compareTo(b.ticker));

    return _Results(inScreen: inScreen, inHistory: inHistory, starred: starred);
  }

  static bool _matches(String ticker, String? name, String upper) =>
      ticker.toUpperCase().contains(upper) ||
      (name != null && name.toUpperCase().contains(upper));

  static int _exactness(String ticker, String upper) =>
      ticker.toUpperCase() == upper ? 0 : 1;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final watchlist = context.watch<WatchlistController>();
    final colors = context.colors;
    final window = appState.selectedWindow;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search ticker or company',
            isDense: true,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _term = '');
                    },
                  ),
          ),
          onChanged: _onChanged,
        ),
        actions: const [
          InfoButton(info: PageInfos.search),
          SizedBox(width: 8),
        ],
      ),
      body: _term.isEmpty
          ? const StatusView(
              icon: Icons.search,
              title: 'Search every market',
              message:
                  'Matches on ticker and company name, across the current '
                  'screen and everything the files publish prices for.',
            )
          : FutureBuilder<_Results>(
              future: _search(appState, watchlist),
              builder: (context, snapshot) {
                final results = snapshot.data;
                if (results == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (results.isEmpty) {
                  return StatusView(
                    icon: Icons.search_off,
                    title: 'No matches for "$_term"',
                    message:
                        'Nothing in the published screens, the price history '
                        'or your watchlist matches that.',
                  );
                }

                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (results.inScreen.isNotEmpty) ...[
                      _GroupHeader(
                        title:
                            'In the ${window.longLabel.toLowerCase()} screen',
                        count: results.inScreen.length,
                        note: 'Published by this run, with its figures.',
                      ),
                      Panel(
                        child: Column(
                          children: [
                            for (final row in results.inScreen) ...[
                              StockTile(
                                row: row,
                                showMarketBadge: true,
                                opensTo: (_) => StockDetailScreen(
                                  market: row.market,
                                  ticker: row.ticker,
                                  initialWindow: row.window,
                                ),
                              ),
                              if (row != results.inScreen.last)
                                Divider(
                                  height: 1,
                                  color: colors.divider,
                                  indent: 66,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (results.inHistory.isNotEmpty) ...[
                      _GroupHeader(
                        title: 'In market history',
                        count: results.inHistory.length,
                        note:
                            'Prices are published for these, but they are not '
                            'in the ${window.longLabel.toLowerCase()} screen.',
                      ),
                      Panel(
                        child: Column(
                          children: [
                            for (final hit in results.inHistory) ...[
                              _HistoryResultTile(hit: hit),
                              if (hit != results.inHistory.last)
                                Divider(
                                  height: 1,
                                  color: colors.divider,
                                  indent: 66,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (results.starred.isNotEmpty) ...[
                      _GroupHeader(
                        title: 'Watchlisted',
                        count: results.starred.length,
                        note:
                            'Starred, but the latest run publishes neither a '
                            'screen row nor prices for them.',
                      ),
                      Panel(
                        child: Column(
                          children: [
                            for (final hit in results.starred) ...[
                              _StarResultTile(hit: hit),
                              if (hit != results.starred.last)
                                Divider(
                                  height: 1,
                                  color: colors.divider,
                                  indent: 66,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

/// A group's title, how many it holds, and why its members are in it.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.count,
    required this.note,
  });

  final String title;
  final int count;
  final String note;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            note,
            style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// An instrument found in the price history rather than the selected screen.
class _HistoryResultTile extends StatelessWidget {
  const _HistoryResultTile({required this.hit});

  final _HistoryHit hit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = hit.ticker;
    final windows = hit.windows;

    return Material(
      color:
          starredRowColor(context, hit.market, row.ticker) ??
          Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StockDetailScreen(
              market: hit.market,
              ticker: row.ticker,
              initialWindow: windows.isEmpty ? null : windows.first,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              TickerAvatar(ticker: row.ticker, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.ticker,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        TagBadge(
                          label: hit.market.label,
                          foreground: colors.neutral,
                          background: colors.neutralSurface,
                        ),
                      ],
                    ),
                    if (row.name != null)
                      Text(
                        row.name!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textName,
                        ),
                      ),
                    const SizedBox(height: 2),
                    // Why it is here, and what it did clear: the difference
                    // between "the run ignored this" and "it passed a
                    // different window".
                    Text(
                      windows.isEmpty
                          ? 'Not in any screen this run'
                          : 'In the ${_labels(windows)} '
                                '${windows.length == 1 ? 'screen' : 'screens'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Fmt.price(row.lastPrice),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  ChangeChip(pctChange: row.pctChange, dense: true),
                ],
              ),
              WatchlistStar(
                market: hit.market,
                ticker: row.ticker,
                dense: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _labels(List<GrowthWindow> windows) =>
      windows.map((window) => window.label).join(' and ');
}

/// A starred ticker the latest run says nothing about.
class _StarResultTile extends StatelessWidget {
  const _StarResultTile({required this.hit});

  final _StarHit hit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color:
          starredRowColor(context, hit.market, hit.ticker) ??
          Colors.transparent,
      child: ListTile(
        leading: TickerAvatar(ticker: hit.ticker, size: 34),
        title: Row(
          children: [
            Flexible(
              child: Text(
                hit.ticker,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            TagBadge(
              label: hit.market.label,
              foreground: colors.neutral,
              background: colors.neutralSurface,
            ),
          ],
        ),
        subtitle: Text(
          hit.name == null
              ? 'Dropped from the latest run'
              : '${hit.name} · dropped from the latest run',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: colors.textTertiary),
        ),
        trailing: WatchlistStar(
          market: hit.market,
          ticker: hit.ticker,
          dense: true,
        ),
      ),
    );
  }
}
