import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/market.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/panels.dart';
import '../widgets/stock_tile.dart';
import 'stock_detail_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// Starred tickers from both markets, with their current window figures.
class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key, this.onSelect, this.selected});

  /// See [MarketListScreen.onSelect]: set by the desktop shell, which shows
  /// the instrument beside the list rather than over it.
  final ValueChanged<StockRow>? onSelect;
  final StockRow? selected;

  Future<List<StockRow>> _load(
    AppState appState,
    WatchlistController watchlist,
  ) async {
    final rows = <StockRow>[];
    for (final market in Market.values) {
      final database = appState.databaseOf(market);
      if (database == null) continue;
      final tickers = watchlist.tickersFor(market);
      if (tickers.isEmpty) continue;
      final window = database.availableWindows.contains(appState.selectedWindow)
          ? appState.selectedWindow
          : (database.availableWindows.isEmpty
                ? null
                : database.availableWindows.first);
      if (window == null) continue;
      rows.addAll(await database.stocks(window, StockQuery(tickers: tickers)));
    }
    rows.sort((a, b) => b.pctChange.compareTo(a.pctChange));
    return rows;
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
              onPressed: () => _confirmClear(context, watchlist),
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
          : FutureBuilder<List<StockRow>>(
              future: _load(appState, watchlist),
              builder: (context, snapshot) {
                final rows = snapshot.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final missing = watchlist.length - rows.length;
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Text(
                        '${rows.length} of ${watchlist.length} starred tickers '
                        'appear in the ${appState.selectedWindow.longLabel.toLowerCase()} window.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    Panel(
                      child: Column(
                        children: [
                          for (final row in rows) ...[
                            Dismissible(
                              key: ValueKey(row.key),
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
                              onDismissed: (_) =>
                                  watchlist.remove(row.market, row.ticker),
                              child: StockTile(
                                row: row,
                                showMarketBadge: true,
                                selected: row.key == selected?.key,
                                onTap: onSelect == null
                                    ? null
                                    : () => onSelect!(row),
                                opensTo: onSelect != null
                                    ? null
                                    : (_) => StockDetailScreen(
                                        market: row.market,
                                        ticker: row.ticker,
                                        initialWindow: row.window,
                                      ),
                              ),
                            ),
                            if (row != rows.last)
                              Divider(
                                height: 1,
                                color: colors.divider,
                                indent: 66,
                              ),
                          ],
                        ],
                      ),
                    ),
                    if (missing > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Text(
                          '$missing starred ${missing == 1 ? 'ticker is' : 'tickers are'} '
                          'not in this window of the latest run.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    WatchlistController watchlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear watchlist?'),
        content: Text(
          'This removes all ${Fmt.integer(watchlist.length)} starred tickers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await watchlist.clear();
  }
}
