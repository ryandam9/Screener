import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/market.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../state/watchlist_controller.dart';
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

/// Everything the dashboard renders, for the one market it is showing.
class _DashboardData {
  const _DashboardData({
    required this.market,
    required this.summary,
    required this.topGainers,
    required this.starred,
    required this.starredTotal,
    required this.runs,
  });

  final Market market;

  /// Null while the file for [market] has not been opened.
  final MarketSummary? summary;

  final List<StockRow> topGainers;

  /// Starred tickers this window lists, strongest first.
  final List<StockRow> starred;

  /// How many are starred in this market altogether, including the ones this
  /// window does not list — see the note under the snapshot.
  final int starredTotal;

  final List<RunInfo> runs;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onSeeAllMarkets, this.onSeeWatchlist});

  final VoidCallback? onSeeAllMarkets;

  /// Opens the watchlist tab, for the snapshot's own "see all".
  final VoidCallback? onSeeWatchlist;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<_DashboardData>? _future;
  String _signature = '';

  /// One market's dashboard.
  ///
  /// Three files pooled into one page put three tall summaries above the rows
  /// someone opened the app to read. A phone shows the market that is
  /// selected, and the strip at the top switches it.
  Future<_DashboardData> _load(
    AppState appState,
    WatchlistController watchlist,
  ) async {
    final market = appState.selectedMarket;
    final window = appState.selectedWindow;
    final starredTotal = watchlist.countFor(market);
    final database = appState.databaseOf(market);

    if (database == null) {
      return _DashboardData(
        market: market,
        summary: null,
        topGainers: const [],
        starred: const [],
        starredTotal: starredTotal,
        runs: const [],
      );
    }

    final hasWindow = database.availableWindows.contains(window);
    final gainers = hasWindow
        ? await database.stocks(window, const StockQuery(limit: 6))
        : <StockRow>[];

    final tickers = watchlist.tickersFor(market);
    final starred = tickers.isEmpty || !hasWindow
        ? <StockRow>[]
        : await database.stocks(window, StockQuery(tickers: tickers));
    starred.sort((a, b) => b.pctChange.compareTo(a.pctChange));

    final runs = await database.allRuns()
      ..sort((a, b) {
        final left = a.runStartedAt;
        final right = b.runStartedAt;
        if (left == null || right == null) {
          return a.window.approximateDays.compareTo(b.window.approximateDays);
        }
        return right.compareTo(left);
      });

    return _DashboardData(
      market: market,
      summary: await database.summary(),
      topGainers: gainers,
      starred: starred,
      starredTotal: starredTotal,
      runs: runs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final watchlist = context.watch<WatchlistController>();
    final colors = context.colors;

    // Reload when the market or window changes, a database is swapped in, or
    // a ticker is starred.
    final signature = [
      appState.selectedMarket.id,
      appState.selectedWindow.name,
      watchlist.keys.join(','),
      for (final market in Market.values)
        '${market.id}:${appState.stateOf(market).asset?.syncedAt.millisecondsSinceEpoch ?? 0}:'
            '${appState.stateOf(market).isReady}',
    ].join('|');
    if (signature != _signature) {
      _signature = signature;
      _future = _load(appState, watchlist);
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
        onRefresh: appState.refreshAll,
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
                    onAction: appState.refreshAll,
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
                if (data.summary == null) return const _DashboardSkeleton();
                return _DashboardBody(
                  data: data,
                  window: appState.selectedWindow,
                  onSeeAllMarkets: widget.onSeeAllMarkets,
                  onSeeWatchlist: widget.onSeeWatchlist,
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
                      ? Icon(Icons.check, color: context.colors.interactive)
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
    this.onSeeWatchlist,
  });

  final _DashboardData data;
  final GrowthWindow window;
  final VoidCallback? onSeeAllMarkets;
  final VoidCallback? onSeeWatchlist;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final market = data.market;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _ContextBar(market: market, window: window),
        const SizedBox(height: 10),
        _MarketStrip(
          market: market,
          summary: data.summary,
          window: window,
          state: context.watch<AppState>().stateOf(market),
        ),
        SectionHeader(
          title: 'Top Gainers (${window.longLabel})',
          actionLabel: 'View all',
          onAction: onSeeAllMarkets,
        ),
        Panel(
          child: data.topGainers.isEmpty
              ? StatusView(
                  icon: Icons.trending_flat,
                  title: 'No ${market.label} rows in this window',
                  compact: true,
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < data.topGainers.length;
                      index++
                    ) ...[
                      GainerTile(
                        row: data.topGainers[index],
                        rank: index + 1,
                        showMarketBadge: false,
                        opensTo: (_) => StockDetailScreen(
                          market: data.topGainers[index].market,
                          ticker: data.topGainers[index].ticker,
                          initialWindow: window,
                        ),
                      ),
                      if (index < data.topGainers.length - 1)
                        Divider(height: 1, color: colors.divider, indent: 54),
                    ],
                  ],
                ),
        ),
        if (data.starredTotal > 0) ...[
          SectionHeader(
            title: 'Watchlist',
            actionLabel: 'See all',
            onAction: onSeeWatchlist,
          ),
          Panel(
            child: data.starred.isEmpty
                ? StatusView(
                    icon: Icons.star_border_rounded,
                    title:
                        'None of your ${market.label} stars are in this window',
                    compact: true,
                  )
                : Column(
                    children: [
                      for (final row in data.starred.take(3)) ...[
                        GainerTile(
                          row: row,
                          showMarketBadge: false,
                          opensTo: (_) => StockDetailScreen(
                            market: row.market,
                            ticker: row.ticker,
                            initialWindow: window,
                          ),
                        ),
                        if (row != data.starred.take(3).last)
                          Divider(height: 1, color: colors.divider, indent: 66),
                      ],
                    ],
                  ),
          ),
          // The snapshot only shows what this window lists. Saying how many
          // are starred altogether keeps it from reading as the whole list —
          // the watchlist tab is the one that shows every star.
          if (data.starred.length < data.starredTotal)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '${data.starred.length} of ${data.starredTotal} starred '
                '${market.label} ${market.instrumentNoun} are in the '
                '${window.longLabel.toLowerCase()} window.',
                style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
              ),
            ),
        ],
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

/// Which file, and which window of it, the page below is about.
///
/// One bar rather than a title menu and a toolbar icon: the two choices that
/// decide every number on the screen were the two that took the most taps to
/// find.
class _ContextBar extends StatelessWidget {
  const _ContextBar({required this.market, required this.window});

  final Market market;
  final GrowthWindow window;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final windows = appState.availableWindows;

    return Panel(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<Market>(
            segments: [
              for (final value in Market.values)
                ButtonSegment(value: value, label: Text(value.label)),
            ],
            selected: {market},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (selection) =>
                appState.selectMarket(selection.first),
          ),
          const SizedBox(height: 8),
          PeriodSelector<GrowthWindow>(
            values: windows,
            selected: windows.contains(window) ? window : windows.first,
            labelOf: (value) => value.label,
            onChanged: appState.selectWindow,
          ),
        ],
      ),
    );
  }
}

/// The selected market in one strip: what the window did, and how fresh it is.
///
/// The old page stacked a full-height card per file above the rows. Three
/// files made that 430dp on a 400dp-wide phone — the whole first screen spent
/// on summaries, with the movers below the fold.
class _MarketStrip extends StatelessWidget {
  const _MarketStrip({
    required this.market,
    required this.summary,
    required this.window,
    required this.state,
  });

  final Market market;
  final MarketSummary? summary;
  final GrowthWindow window;

  /// The download behind this strip, for the refresh stamp.
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

    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (stat == null || stat.count == 0)
                      Text(
                        summary == null ? 'Loading…' : 'No rows',
                        style: TextStyle(
                          fontSize: 20,
                          color: colors.textTertiary,
                        ),
                      )
                    else ...[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          Fmt.signedPercent(stat.medianPctChange, decimals: 2),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.6,
                            color: colors.forChange(stat.medianPctChange),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'median ${window.label} · '
                        '${Fmt.integer(stat.count)} ${market.instrumentNoun}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trend.length >= 2) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 92,
                  height: 36,
                  child: Sparkline(values: trend, color: colors.positive),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          RefreshStamp(state: state, dense: true),
        ],
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
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
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
              // A column of its own rather than a loose Flexible, which claims
              // a share of the row's free space and leaves what it does not use
              // stranded after it. Sized to the longest stamp this prints —
              // "Yesterday, 11:37 AM", 110px in Inter — and never more than the
              // row can spare.
              SizedBox(
                width: math.min(
                  MediaQuery.textScalerOf(context).scale(120),
                  constraints.maxWidth * 0.4,
                ),
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
            onTap: () => context.read<AppState>().refreshAll(),
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
