import 'dart:math' as math;

import 'package:animations/animations.dart';
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
import '../widgets/brutal.dart';
import '../widgets/panels.dart';
import '../widgets/refresh_stamp.dart';
import '../widgets/watchlist_highlight.dart';
import '../widgets/watchlist_star.dart';
import 'market_list_screen.dart';
import 'search_screen.dart';
import 'stock_detail_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// Everything the dashboard renders, for the one market it is showing.
class _DashboardData {
  const _DashboardData({
    required this.market,
    required this.topGainers,
    required this.starred,
    required this.starredTotal,
    required this.runs,
  });

  final Market market;

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
                late final String transitionKey;
                late final Widget child;
                if (snapshot.hasError) {
                  transitionKey = 'error';
                  child = StatusView(
                    icon: Icons.error_outline,
                    title: 'Could not read the databases',
                    message: '${snapshot.error}',
                    actionLabel: 'Retry',
                    onAction: appState.refreshAll,
                  );
                } else {
                  final data = snapshot.data;
                  if (data == null || !appState.stateOf(data.market).isReady) {
                    transitionKey =
                        'loading-${appState.selectedMarket.id}-'
                        '${appState.selectedWindow.name}';
                    child = _DashboardSkeleton(window: appState.selectedWindow);
                  } else {
                    transitionKey =
                        'ready-${data.market.id}-'
                        '${appState.selectedWindow.name}';
                    child = _DashboardBody(
                      data: data,
                      window: appState.selectedWindow,
                      onSeeAllMarkets: widget.onSeeAllMarkets,
                      onSeeWatchlist: widget.onSeeWatchlist,
                    );
                  }
                }

                return PageTransitionSwitcher(
                  duration: AppMotion.contentDuration(context),
                  transitionBuilder: (child, animation, secondaryAnimation) =>
                      FadeThroughTransition(
                        animation: animation,
                        secondaryAnimation: secondaryAnimation,
                        fillColor: colors.pageBackground,
                        child: child,
                      ),
                  child: KeyedSubtree(
                    key: ValueKey(transitionKey),
                    child: child,
                  ),
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
    final gainers = data.topGainers;
    // Every bar on the page is drawn against the strongest move on it, so the
    // leader's bar is always full and the rest read as fractions of it.
    final peak = gainers.isEmpty
        ? 1.0
        : gainers.map((row) => row.pctChange.abs()).reduce(math.max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Masthead(market: market, window: window),
        _ContextBar(market: market, window: window),
        if (gainers.isEmpty)
          BrutalBox(
            margin: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: StatusView(
              icon: Icons.trending_flat,
              title: 'No ${market.label} rows in this window',
              compact: true,
            ),
          )
        else ...[
          _HeroGainer(row: gainers.first, window: window),
          if (gainers.length > 1) ...[
            BrutalHeading(
              title: 'Runners-up',
              actionLabel: 'All',
              onAction: onSeeAllMarkets,
            ),
            for (var index = 1; index < gainers.length; index++)
              _RankRow(
                row: gainers[index],
                rank: index + 1,
                peak: peak,
                window: window,
              ),
          ],
        ],
        if (data.starredTotal > 0) ...[
          BrutalHeading(
            title: 'Watchlist',
            actionLabel: 'All',
            onAction: onSeeWatchlist,
          ),
          if (data.starred.isEmpty)
            BrutalBox(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: StatusView(
                icon: Icons.star_border_rounded,
                title: 'None of your ${market.label} stars are in this window',
                compact: true,
              ),
            )
          else
            for (final row in data.starred.take(3))
              _RankRow(row: row, peak: peak, window: window, starred: true),
          // The snapshot only shows what this window lists. Saying how many
          // are starred altogether keeps it from reading as the whole list —
          // the watchlist tab is the one that shows every star.
          if (data.starred.length < data.starredTotal)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                '${data.starred.length} of ${data.starredTotal} starred '
                '${market.label} ${market.instrumentNoun} are in the '
                '${window.longLabel.toLowerCase()} window.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textTertiary,
                ),
              ),
            ),
        ],
        const BrutalHeading(title: 'Recent analyses'),
        BrutalBox(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            children: [
              for (final run in data.runs.take(4)) ...[
                _RunTile(run: run),
                if (run != data.runs.take(4).last)
                  Container(height: AppBrut.hairline, color: colors.ink),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The top of the poster: what file you are reading, in the largest type on
/// the screen.
///
/// The app bar carries only the actions. A market's name set at 44px against a
/// rule is what tells you where you are — a 20px title in a bar is what every
/// other app does.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.market, required this.window});

  final Market market;
  final GrowthWindow window;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: AppBrut.border + 1.5, color: colors.ink),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    market.label.toUpperCase(),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 44,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2.4,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              BrutalTag(
                label: '${window.label} screen',
                fill: colors.warningSurface,
                foreground: colors.onAccent,
                fontSize: 10.5,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            market.longName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Container(height: AppBrut.hairline, color: colors.ink),
        ],
      ),
    );
  }
}

/// The leader, given the whole width and the biggest type on the page.
///
/// A ranked list whose first row looks like its fourth wastes the one thing
/// the screener actually produces: a single name that moved more than anything
/// else this week. Here that name is the poster.
class _HeroGainer extends StatelessWidget {
  const _HeroGainer({required this.row, required this.window});

  final StockRow row;
  final GrowthWindow window;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return BrutalPressable(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      // A starred ticker is marked wherever it is listed, so the wash belongs
      // here too — it is the card's fill rather than a tint laid over it.
      fill: starredRowColor(context, row.market, row.ticker) ?? colors.card,
      semanticLabel:
          'Top gainer ${row.ticker}, ${row.shortName}, '
          'up ${row.pctChange.toStringAsFixed(1)} percent',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StockDetailScreen(
            market: row.market,
            ticker: row.ticker,
            initialWindow: window,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BrutalTag(
                label: 'No. 1 this ${window.label}',
                fill: colors.interactive,
                foreground: colors.onInteractive,
              ),
              const Spacer(),
              WatchlistStar(
                market: row.market,
                ticker: row.ticker,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              row.ticker,
              maxLines: 1,
              style: TextStyle(
                fontSize: 52,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -2.6,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            row.shortName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: colors.textName,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: DeltaBlock(pctChange: row.pctChange, fontSize: 24),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    row.market.money(row.latestPrice),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One of the runners-up: rank, ticker, name, and a bar drawn to scale against
/// the strongest move on the page.
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.row,
    required this.peak,
    required this.window,
    this.rank,
    this.starred = false,
  });

  final StockRow row;
  final double peak;
  final GrowthWindow window;
  final int? rank;

  /// Drawn on the watchlist strip, where a rank would be meaningless.
  final bool starred;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final share = peak <= 0
        ? 0.0
        : (row.pctChange.abs() / peak).clamp(0.0, 1.0);

    return BrutalPressable(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(0, 0, 6, 0),
      fill: starredRowColor(context, row.market, row.ticker) ?? colors.card,
      semanticLabel:
          '${row.ticker}, ${row.shortName}, '
          'up ${row.pctChange.toStringAsFixed(1)} percent',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StockDetailScreen(
            market: row.market,
            ticker: row.ticker,
            initialWindow: window,
          ),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The rank sits in its own inked column rather than floating in the
            // row, so the list reads as a numbered chart down the left edge.
            Container(
              width: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: starred ? colors.warningSurface : colors.neutralSurface,
                border: Border(
                  right: BorderSide(color: colors.ink, width: AppBrut.hairline),
                ),
              ),
              child: starred
                  ? Icon(Icons.star_rounded, size: 18, color: colors.onAccent)
                  : Text(
                      '${rank ?? ''}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        color: colors.onAccent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 0, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.ticker,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          row.market.money(row.latestPrice),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 2),
                        // Starring from a list row, without opening it, is the
                        // fastest thing this app does. It survives the redesign.
                        WatchlistStar(
                          market: row.market,
                          ticker: row.ticker,
                          dense: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      row.shortName,
                      // Three lines, not one: the name is often the only way
                      // to tell what a four-letter ticker is, and this row is
                      // narrow enough that one line would cut most of them
                      // mid-word. The row grows instead.
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: colors.textName,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        DeltaBlock(pctChange: row.pctChange, dense: true),
                        const SizedBox(width: 8),
                        // The bar is what makes the ranks worth reading as a
                        // group: second place being a third of first place is
                        // invisible in a column of percentages.
                        Expanded(
                          child: _MagnitudeBar(
                            share: share,
                            fill: row.pctChange >= 0
                                ? colors.positiveSurface
                                : colors.negativeSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A hard-edged bar: an inked track with a saturated fill across [share] of it.
class _MagnitudeBar extends StatelessWidget {
  const _MagnitudeBar({required this.share, required this.fill});

  final double share;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 10,
      decoration: BoxDecoration(
        border: Border.all(color: colors.ink, width: AppBrut.hairline),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: share.clamp(0.02, 1.0),
          heightFactor: 1,
          child: ColoredBox(color: fill),
        ),
      ),
    );
  }
}

/// Which file, and which window of it, the page below is about.
///
/// Blocks rather than a segmented control and a row of pills: the two choices
/// that decide every number on the screen are the two loudest controls on it.
class _ContextBar extends StatelessWidget {
  const _ContextBar({required this.market, required this.window});

  final Market market;
  final GrowthWindow window;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.colors;
    final windows = appState.availableWindows;
    final selected = windows.contains(window) ? window : windows.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final value in Market.values) ...[
                if (value != Market.values.first) const SizedBox(width: 7),
                Expanded(
                  child: _Block(
                    key: ValueKey('market-block-${value.id}'),
                    label: value.label,
                    selected: value == market,
                    fill: colors.interactive,
                    foreground: colors.onInteractive,
                    onTap: () => appState.selectMarket(value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              for (final value in windows) ...[
                if (value != windows.first) const SizedBox(width: 6),
                Expanded(
                  child: _Block(
                    key: ValueKey('window-block-${value.name}'),
                    label: value.label,
                    selected: value == selected,
                    fill: colors.ink,
                    foreground: colors.card,
                    dense: true,
                    onTap: () => appState.selectWindow(value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          RefreshStamp(state: appState.stateOf(market), dense: true),
        ],
      ),
    );
  }
}

/// One square control. Selected means filled; unselected means outlined.
class _Block extends StatelessWidget {
  const _Block({
    super.key,
    required this.label,
    required this.selected,
    required this.fill,
    required this.foreground,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final Color fill;
  final Color foreground;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: AppMotion.selectionDuration(context),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(vertical: dense ? 6 : 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? fill : colors.card,
            border: Border.all(color: colors.ink, width: AppBrut.border),
          ),
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: dense ? 11.5 : 13,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: selected ? foreground : colors.textPrimary,
            ),
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

class _DashboardSkeleton extends StatefulWidget {
  const _DashboardSkeleton({required this.window});

  final GrowthWindow window;

  @override
  State<_DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<_DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool? _animationsDisabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (_animationsDisabled == disabled) return;
    _animationsDisabled = disabled;
    if (disabled) {
      _pulse
        ..stop()
        ..value = 0.55;
    } else {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final boneColor = Color.lerp(
          colors.neutralSurface,
          colors.interactiveSurface,
          0.12 + (_pulse.value * 0.28),
        )!;

        Widget bone({
          required double height,
          double? width,
          bool round = false,
        }) {
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: boneColor,
              shape: round ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: round ? null : BorderRadius.circular(height / 2),
            ),
          );
        }

        Widget row({bool compact = false}) {
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: compact ? 10 : 12,
            ),
            child: Row(
              children: [
                bone(
                  height: compact ? 30 : 36,
                  width: compact ? 30 : 36,
                  round: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: compact ? 0.42 : 0.34,
                        child: bone(height: 12),
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: compact ? 0.62 : 0.76,
                        child: bone(height: 9),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                bone(height: 12, width: compact ? 48 : 58),
              ],
            ),
          );
        }

        return Semantics(
          liveRegion: true,
          label: 'Preparing dashboard',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.interactiveSurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.auto_graph_rounded,
                        size: 20,
                        color: colors.interactive,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Preparing dashboard',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Building the ${widget.window.longLabel.toLowerCase()} rankings',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const BrutalHeading(title: 'Runners-up'),
              Panel(
                child: Column(
                  children: [
                    for (var index = 0; index < 4; index++) ...[
                      row(),
                      if (index < 3)
                        Divider(height: 1, color: colors.divider, indent: 62),
                    ],
                  ],
                ),
              ),
              const BrutalHeading(title: 'Recent analyses'),
              Panel(
                child: Column(
                  children: [
                    row(compact: true),
                    Divider(height: 1, color: colors.divider, indent: 16),
                    row(compact: true),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
