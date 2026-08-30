import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/market.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/panels.dart';
import '../widgets/refresh_stamp.dart';
import '../widgets/sparkline.dart';
import '../widgets/stock_tile.dart';
import 'market_list_screen.dart';
import 'search_screen.dart';
import 'stock_detail_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// Everything the dashboard renders, gathered in one pass over every market.
class _DashboardData {
  const _DashboardData({
    required this.summaries,
    required this.topGainers,
    required this.runs,
  });

  final Map<Market, MarketSummary> summaries;
  final List<StockRow> topGainers;
  final List<RunInfo> runs;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onSeeAllMarkets});

  final VoidCallback? onSeeAllMarkets;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<_DashboardData>? _future;
  String _signature = '';

  Future<_DashboardData> _load(AppState appState) async {
    final window = appState.selectedWindow;
    final summaries = <Market, MarketSummary>{};
    final gainers = <StockRow>[];
    final runs = <RunInfo>[];

    for (final market in Market.values) {
      final database = appState.databaseOf(market);
      if (database == null) continue;
      summaries[market] = await database.summary();
      runs.addAll(await database.allRuns());
      if (database.availableWindows.contains(window)) {
        gainers.addAll(
          await database.stocks(window, const StockQuery(limit: 6)),
        );
      }
    }

    gainers.sort((a, b) => b.pctChange.compareTo(a.pctChange));
    runs.sort((a, b) {
      final left = a.runStartedAt;
      final right = b.runStartedAt;
      if (left == null || right == null) {
        return a.window.approximateDays.compareTo(b.window.approximateDays);
      }
      return right.compareTo(left);
    });

    return _DashboardData(
      summaries: summaries,
      topGainers: gainers.take(4).toList(),
      runs: runs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.colors;

    // Reload when a database is swapped in or the window changes.
    final signature = [
      appState.selectedWindow.name,
      for (final market in Market.values)
        '${market.id}:${appState.stateOf(market).asset?.syncedAt.millisecondsSinceEpoch ?? 0}:'
            '${appState.stateOf(market).isReady}',
    ].join('|');
    if (signature != _signature) {
      _signature = signature;
      _future = _load(appState);
    }

    return Scaffold(
      appBar: AppBar(
        // Three actions and a 20px title do not both fit at 320dp, and the
        // app's own name is a poor thing to ellipsize.
        title: Text(
          'Stocks Analysis',
          style: MediaQuery.sizeOf(context).width < 360
              ? const TextStyle(fontSize: 17)
              : null,
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Window',
            icon: const Icon(Icons.tune),
            onPressed: () => _showWindowPicker(context, appState),
          ),
          const InfoButton(info: PageInfos.dashboard),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => appState.refreshAll(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            const _SyncBanner(),
            FutureBuilder<_DashboardData>(
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
                if (data == null) {
                  if (!appState.anyReady) return const _DashboardSkeleton();
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (data.summaries.isEmpty) return const _DashboardSkeleton();
                return _DashboardBody(
                  data: data,
                  window: appState.selectedWindow,
                  onSeeAllMarkets: widget.onSeeAllMarkets,
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text(
                'Screener output, not live quotes. Prices are the window '
                'endpoints published by the pipeline.',
                style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWindowPicker(BuildContext context, AppState appState) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const SectionHeader(
                title: 'Analysis window',
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              ),
              for (final window in GrowthWindow.values)
                ListTile(
                  title: Text('${window.longLabel} analysis'),
                  trailing: window == appState.selectedWindow
                      ? Icon(Icons.check, color: context.colors.positive)
                      : null,
                  onTap: () {
                    appState.selectWindow(window);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.window,
    this.onSeeAllMarkets,
  });

  final _DashboardData data;
  final GrowthWindow window;
  final VoidCallback? onSeeAllMarkets;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _MarketCards(summaries: data.summaries, window: window),
        ),
        SectionHeader(
          title: 'Top Gainers (${window.longLabel})',
          actionLabel: 'View all',
          onAction: onSeeAllMarkets,
        ),
        Panel(
          child: data.topGainers.isEmpty
              ? const StatusView(
                  icon: Icons.trending_flat,
                  title: 'No rows in this window',
                  compact: true,
                )
              : Column(
                  children: [
                    for (final row in data.topGainers) ...[
                      GainerTile(
                        row: row,
                        opensTo: (_) => StockDetailScreen(
                          market: row.market,
                          ticker: row.ticker,
                          initialWindow: window,
                        ),
                      ),
                      if (row != data.topGainers.last)
                        Divider(height: 1, color: colors.divider, indent: 66),
                    ],
                  ],
                ),
        ),
        const SectionHeader(title: 'Recent Analyses'),
        Panel(
          child: Column(
            children: [
              for (final run in data.runs.take(4)) ...[
                _RunTile(run: run),
                if (run != data.runs.take(4).last)
                  Divider(height: 1, color: colors.divider, indent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The market cards at the top of the dashboard, in as many columns as fit.
///
/// One row across was right for two files. A third makes each card 108dp on a
/// 360dp phone, which is narrower than the headline percentage — "+117.91%"
/// wrapped onto a second line, and onto a third at the largest text sizes. So
/// the strip breaks into a grid instead: two up on a phone, all of them across
/// wherever there is room.
class _MarketCards extends StatelessWidget {
  const _MarketCards({required this.summaries, required this.window});

  final Map<Market, MarketSummary> summaries;
  final GrowthWindow window;

  /// Below this a card cannot hold its own headline. Scaled with the reader's
  /// text size, since that is what the number's width follows.
  static const double _minCardWidth = 132;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final markets = Market.values;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minimum = MediaQuery.textScalerOf(context).scale(_minCardWidth);
        final columns = ((constraints.maxWidth + _gap) / (minimum + _gap))
            .floor()
            .clamp(1, markets.length);

        final rows = <Widget>[];
        for (var start = 0; start < markets.length; start += columns) {
          final chunk = markets.skip(start).take(columns).toList();
          rows.add(
            // IntrinsicHeight gives the row a definite height, so its cards
            // can stretch to match the tallest. Without it, `stretch` inside
            // the scrolling column asks for infinite height.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i != 0) const SizedBox(width: _gap),
                    // A short last row keeps the column width of the rows
                    // above it: a lone card stretched across the screen would
                    // read as a different kind of card altogether.
                    Expanded(
                      child: i < chunk.length
                          ? _MarketCard(
                              market: chunk[i],
                              summary: summaries[chunk[i]],
                              window: window,
                              state: appState.stateOf(chunk[i]),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i != 0) const SizedBox(height: _gap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

/// One market's card at the top of the dashboard.
///
/// The published data has no index level, so the headline number is the median
/// percentage change of the window and the sparkline is that median across
/// every window the file contains.
class _MarketCard extends StatelessWidget {
  const _MarketCard({
    required this.market,
    required this.summary,
    required this.window,
    required this.state,
  });

  final Market market;
  final MarketSummary? summary;
  final GrowthWindow window;

  /// The download behind this card, for the refresh stamp.
  final MarketState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final summary = this.summary;
    final stat = summary?.statFor(window);
    final trend = [
      for (final entry in summary?.stats ?? const <WindowStat>[])
        if (entry.count > 0) entry.medianPctChange,
    ];

    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.cardBorder),
      ),
      child: InkWell(
        onTap: summary == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      MarketListScreen(market: market, initialWindow: window),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                market.label,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                market.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: trend.length >= 2
                    ? Sparkline(values: trend, color: colors.positive)
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 10),
              if (stat == null || stat.count == 0)
                Text(
                  summary == null ? 'Loading…' : 'No rows',
                  style: TextStyle(fontSize: 15, color: colors.textTertiary),
                )
              else ...[
                Text(
                  Fmt.signedPercent(stat.medianPctChange, decimals: 2),
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.6,
                    color: colors.forChange(stat.medianPctChange),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'median ${window.label} · ${Fmt.integer(stat.count)} ${market.instrumentNoun}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                ),
              ],
              const SizedBox(height: 8),
              RefreshStamp(state: state, dense: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});

  final RunInfo run;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final startedAt = run.runStartedAt;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MarketListScreen(market: run.market, initialWindow: run.window),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${run.market.label} - ${run.window.longLabel} Analysis',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${Fmt.integer(run.rowCount)} ${run.market.instrumentNoun} analyzed',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                startedAt == null
                    ? Fmt.date(run.dataAsOf)
                    : Fmt.relativeStamp(startedAt),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress / offline strip shown above the dashboard content.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.colors;

    final busy = Market.values
        .where((m) => appState.stateOf(m).isBusy)
        .toList();
    if (busy.isNotEmpty) {
      final state = appState.stateOf(busy.first);
      final label = switch (state.phase) {
        SyncPhase.downloading => 'Downloading ${busy.first.objectKey}',
        SyncPhase.opening => 'Opening ${busy.first.objectKey}',
        _ => 'Checking ${busy.first.objectKey} for updates',
      };
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.neutralSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: state.progress,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                state.progress == null
                    ? label
                    : '$label · ${(state.progress! * 100).round()}%',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final failed = Market.values
        .where((m) => appState.stateOf(m).error != null)
        .toList();
    if (failed.isEmpty) return const SizedBox.shrink();

    final offline = failed.every((m) => appState.stateOf(m).database != null);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: offline ? colors.warningSurface : colors.negativeSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            offline ? Icons.cloud_off : Icons.error_outline,
            size: 17,
            color: offline ? colors.warning : colors.negative,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              offline
                  ? 'Showing cached data — could not reach S3.'
                  : 'Could not load ${failed.map((m) => m.objectKey).join(', ')}.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: offline ? colors.warning : colors.negative,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => context.read<AppState>().refreshAll(force: true),
            child: Text(
              'Retry',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: offline ? colors.warning : colors.negative,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget block(double height) => Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: block(150)),
              const SizedBox(width: 12),
              Expanded(child: block(150)),
            ],
          ),
          block(220),
          block(150),
        ],
      ),
    );
  }
}
