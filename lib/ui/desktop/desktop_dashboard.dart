import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/market.dart';
import '../../models/price_bar.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../screens/stock_detail_screen.dart';
import '../widgets/panels.dart';
import '../widgets/price_chart.dart';
import 'widgets/desktop_cards.dart';
import 'widgets/gainers_table.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// Everything the desktop dashboard shows, gathered in one pass.
class DesktopDashboardData {
  const DesktopDashboardData({
    required this.summaries,
    required this.topGainers,
    required this.movers,
    required this.runs,
    required this.watchlistRows,
    required this.analysesCount,
    required this.rowsAnalysed,
    required this.averageReturn,
    required this.growthSeries,
  });

  final Map<Market, MarketSummary> summaries;
  final List<StockRow> topGainers;
  final List<StockRow> movers;
  final List<RunInfo> runs;

  /// Watchlisted rows present in the selected window, both markets.
  final List<StockRow> watchlistRows;

  /// Number of (market, window) tables the two files publish.
  final int analysesCount;

  /// Total rows across every window of both files.
  ///
  /// Not a distinct instrument count: a ticker present in five windows
  /// contributes five rows, which is why the card labels this "Rows".
  final int rowsAnalysed;

  /// Mean percentage change in the selected window, across both markets.
  final double? averageReturn;

  /// Weekly growth curve per market, from the published price history.
  final Map<Market, List<GrowthPoint>> growthSeries;

  /// Median percentage change of the watchlisted rows, or null when empty.
  double? get watchlistMedian {
    if (watchlistRows.isEmpty) return null;
    final values = [for (final row in watchlistRows) row.pctChange]..sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }
}

class DesktopDashboard extends StatefulWidget {
  const DesktopDashboard({
    super.key,
    this.onSearchSubmitted,
    this.onViewAllGainers,
  });

  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onViewAllGainers;

  @override
  State<DesktopDashboard> createState() => _DesktopDashboardState();
}

class _DesktopDashboardState extends State<DesktopDashboard> {
  final TextEditingController _search = TextEditingController();
  Future<DesktopDashboardData>? _future;
  String _signature = '';

  /// The security charted below the table. Defaults to the strongest mover
  /// and follows whichever row is clicked.
  StockRow? _selected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<DesktopDashboardData> _load(
    AppState appState,
    WatchlistController watchlist,
  ) async {
    final window = appState.selectedWindow;
    final summaries = <Market, MarketSummary>{};
    final gainers = <StockRow>[];
    final movers = <StockRow>[];
    final runs = <RunInfo>[];
    final watched = <StockRow>[];
    final growth = <Market, List<GrowthPoint>>{};

    var analyses = 0;
    var instruments = 0;
    var weightedSum = 0.0;
    var weightedCount = 0;

    for (final market in Market.values) {
      final database = appState.databaseOf(market);
      if (database == null) continue;

      final summary = await database.summary();
      summaries[market] = summary;
      analyses += database.availableWindows.length;
      for (final stat in summary.stats) {
        instruments += stat.count;
      }

      runs.addAll(await database.allRuns());

      // Memoised inside MarketDatabase: the full curve is ~650ms to build and
      // the dashboard rebuilds often.
      final curve = await database.medianGrowthSeries();
      if (curve.isNotEmpty) growth[market] = curve;

      if (database.availableWindows.contains(window)) {
        gainers.addAll(
          await database.stocks(window, const StockQuery(limit: 8)),
        );

        final average = await database.averagePctChange(window);
        final stat = summary.statFor(window);
        if (average != null && stat != null && stat.count > 0) {
          weightedSum += average * stat.count;
          weightedCount += stat.count;
        }

        final tickers = watchlist.tickersFor(market);
        if (tickers.isNotEmpty) {
          watched.addAll(
            await database.stocks(window, StockQuery(tickers: tickers)),
          );
        }
      }

      final shortest = database.availableWindows.isEmpty
          ? null
          : database.availableWindows.first;
      if (shortest != null) {
        movers.addAll(
          await database.stocks(shortest, const StockQuery(limit: 5)),
        );
      }
    }

    gainers.sort((a, b) => b.pctChange.compareTo(a.pctChange));
    movers.sort((a, b) => b.pctChange.compareTo(a.pctChange));
    runs.sort((a, b) {
      final left = a.runStartedAt;
      final right = b.runStartedAt;
      if (left == null || right == null) {
        return a.window.approximateDays.compareTo(b.window.approximateDays);
      }
      return right.compareTo(left);
    });

    return DesktopDashboardData(
      summaries: summaries,
      topGainers: gainers.take(8).toList(),
      movers: movers.take(5).toList(),
      runs: runs,
      watchlistRows: watched,
      analysesCount: analyses,
      rowsAnalysed: instruments,
      averageReturn: weightedCount == 0 ? null : weightedSum / weightedCount,
      growthSeries: growth,
    );
  }

  /// The selection survives a reload when the ticker is still listed;
  /// otherwise it falls back to the strongest mover.
  StockRow? _resolveSelection(DesktopDashboardData data) {
    if (data.topGainers.isEmpty) return null;
    final current = _selected;
    if (current != null) {
      for (final row in data.topGainers) {
        if (row.ticker == current.ticker && row.market == current.market) {
          return row;
        }
      }
    }
    return data.topGainers.first;
  }

  void _openStock(StockRow row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StockDetailScreen(
          market: row.market,
          ticker: row.ticker,
          initialWindow: row.window,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final watchlist = context.watch<WatchlistController>();
    final colors = context.colors;

    final signature = [
      appState.selectedWindow.name,
      watchlist.length.toString(),
      for (final market in Market.values)
        '${market.id}:${appState.stateOf(market).asset?.syncedAt.millisecondsSinceEpoch ?? 0}'
            ':${appState.stateOf(market).isReady}',
    ].join('|');
    if (signature != _signature) {
      _signature = signature;
      _future = _load(appState, watchlist);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(controller: _search, onSubmitted: widget.onSearchSubmitted),
        Container(height: 1, color: colors.cardBorder),
        Expanded(
          child: FutureBuilder<DesktopDashboardData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return StatusView(
                  icon: Icons.error_outline,
                  title: 'Could not read the databases',
                  message: '${snapshot.error}',
                  actionLabel: 'Retry',
                  onAction: () => appState.refreshAll(force: true),
                );
              }
              final data = snapshot.data;
              if (data == null || data.summaries.isEmpty) {
                return Center(
                  child: appState.anyBusy || data == null
                      ? const CircularProgressIndicator()
                      : StatusView(
                          icon: Icons.cloud_off,
                          title: 'No data yet',
                          message: 'The databases have not been downloaded.',
                          actionLabel: 'Download',
                          onAction: () => appState.refreshAll(force: true),
                        ),
                );
              }
              // Keep the selection valid across reloads and window changes.
              final selected = _resolveSelection(data);
              if (selected == null) {
                return const Center(child: Text('No rows in this window'));
              }
              return _DashboardBody(
                data: data,
                window: appState.selectedWindow,
                selected: selected,
                onSelect: (row) => setState(() => _selected = row),
                onOpenStock: _openStock,
                onViewAllGainers: widget.onViewAllGainers,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appState = context.watch<AppState>();

    return Container(
      color: colors.card,
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
      child: Row(
        children: [
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) onSubmitted?.call(value.trim());
              },
              decoration: const InputDecoration(
                hintText: 'Search stocks, ETFs, or analyses…',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 19),
              ),
            ),
          ),
          const SizedBox(width: 14),
          _WindowDropdown(appState: appState),
          const SizedBox(width: 14),
          _SyncButton(appState: appState),
          const SizedBox(width: 6),
          // The desktop dashboard draws its own top bar, so it needs its own
          // info button; every other section keeps the one in its app bar.
          const InfoButton(info: PageInfos.dashboard, dense: true),
          const Spacer(),
        ],
      ),
    );
  }
}

class _WindowDropdown extends StatelessWidget {
  const _WindowDropdown({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.cardBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<GrowthWindow>(
          value: appState.selectedWindow,
          isDense: true,
          borderRadius: BorderRadius.circular(10),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
          items: [
            for (final window in GrowthWindow.values)
              DropdownMenuItem(value: window, child: Text(window.label)),
          ],
          onChanged: (value) {
            if (value != null) appState.selectWindow(value);
          },
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final busy = appState.anyBusy;

    return OutlinedButton.icon(
      onPressed: busy ? null : () => appState.refreshAll(force: true),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textSecondary,
        side: BorderSide(color: colors.cardBorder),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 17),
      label: Text(busy ? 'Syncing…' : 'Refresh'),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.window,
    required this.selected,
    required this.onSelect,
    required this.onOpenStock,
    this.onViewAllGainers,
  });

  final DesktopDashboardData data;
  final GrowthWindow window;
  final StockRow selected;
  final ValueChanged<StockRow> onSelect;
  final ValueChanged<StockRow> onOpenStock;
  final VoidCallback? onViewAllGainers;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final market in Market.values) ...[
                  Expanded(
                    child: MarketSummaryCard(
                      title: '${market.label} Market',
                      subtitle: market.longName,
                      summary: data.summaries[market],
                      window: window,
                      instrumentNoun: market.instrumentNoun,
                      trend: data.growthSeries[market] ?? const [],
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: WatchlistPerformanceCard(
                    median: data.watchlistMedian,
                    count: data.watchlistRows.length,
                    window: window,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AnalysisSummaryCard(
                    analyses: data.analysesCount,
                    rows: data.rowsAnalysed,
                    averageReturn: data.averageReturn,
                    window: window,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 62,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DesktopPanel(
                      title: 'Top Gainers (${window.longLabel})',
                      actionLabel: 'View all',
                      onAction: onViewAllGainers,
                      child: GainersTable(
                        rows: data.topGainers,
                        selected: selected,
                        onTap: onSelect,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SecurityChart(
                      row: selected,
                      onOpenDetails: () => onOpenStock(selected),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 38,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DesktopPanel(
                      title: 'Recent Analyses',
                      child: Column(
                        children: [
                          for (final run in data.runs.take(5)) ...[
                            _RunRow(run: run),
                            if (run != data.runs.take(5).last)
                              Divider(
                                height: 1,
                                color: colors.divider,
                                indent: 18,
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    DesktopPanel(
                      title: 'Top Movers (shortest window)',
                      child: Column(
                        children: [
                          for (final row in data.movers) ...[
                            _MoverRow(row: row, onTap: () => onOpenStock(row)),
                            if (row != data.movers.last)
                              Divider(
                                height: 1,
                                color: colors.divider,
                                indent: 18,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Screener output, not live quotes. Prices are the window endpoints '
            'published by the pipeline.',
            style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Weekly price history for the security selected in the table.
class _SecurityChart extends StatelessWidget {
  const _SecurityChart({required this.row, required this.onOpenDetails});

  final StockRow row;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final database = context.watch<AppState>().databaseOf(row.market);

    return DesktopPanel(
      title: '${row.ticker} · ${row.shortName}',
      actionLabel: 'Open details',
      onAction: onOpenDetails,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
        child: FutureBuilder<List<PriceBar>>(
          // Keyed by ticker so switching rows reloads.
          key: ValueKey('${row.market.id}-${row.ticker}'),
          future: database?.priceHistory(row.ticker),
          builder: (context, snapshot) {
            final bars = snapshot.data;
            if (bars == null) {
              return const SizedBox(
                height: 236,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            // The whole published year, not the table's window: a seven-day
            // window holds two weekly closes, which is a line rather than a
            // history, and this panel exists to show the security itself.
            final plotted = bars;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PriceChart(
                  points: ChartPoint.fromBars(plotted),
                  lineColor: colors.forChange(row.pctChange),
                  height: 236,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Text(
                    plotted.isEmpty
                        ? 'No weekly prices published for ${row.ticker}.'
                        : '${plotted.length} weekly closes, '
                              'the full published history · click a row above '
                              'to chart it.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});

  final RunInfo run;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final startedAt = run.runStartedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.positiveSurface,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.insights, size: 17, color: colors.positive),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${run.market.label} - ${run.window.longLabel} Analysis',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.integer(run.rowCount)} ${run.market.instrumentNoun} analyzed',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            startedAt == null
                ? Fmt.date(run.dataAsOf)
                : Fmt.relativeStamp(startedAt),
            style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _MoverRow extends StatelessWidget {
  const _MoverRow({required this.row, required this.onTap});

  final StockRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            TickerChip(ticker: row.ticker),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                row.shortName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Fmt.price(row.latestPrice),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: Text(
                Fmt.signedPercent(row.pctChange, decimals: 1),
                textAlign: TextAlign.right,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.forChange(row.pctChange),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
