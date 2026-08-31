import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/market.dart';
import '../../models/price_bar.dart';
import '../../models/price_series.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/trend.dart';
import '../responsive.dart';
import '../widgets/category_chip.dart';
import '../widgets/change_chip.dart';
import '../widgets/google_finance_button.dart';
import '../widgets/panels.dart';
import '../widgets/screen_reason.dart';
import '../widgets/price_chart.dart';
import '../widgets/readable_width.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// The three questions this screen answers, in the order they get asked:
/// what is this, how has it done, and what is under the numbers.
///
/// Four sections split that badly. "Windows" and "Overview" were both about
/// how the ticker has performed, and "Links" was two panels — one of them a
/// list of the same URL per window — carrying a whole destination of its own.
enum _DetailTab {
  overview('Overview', Icons.description_outlined),
  performance('Performance', Icons.show_chart),
  metrics('Metrics', Icons.bar_chart_outlined);

  const _DetailTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Everything one ticker's screens need.
class _TickerData {
  const _TickerData({
    required this.rows,
    required this.volumePercentile,
    this.bars = const [],
  });

  /// One row per window that contains this ticker, shortest window first.
  final List<StockRow> rows;

  /// A year of weekly bars, oldest first. Empty for files published before the
  /// history table existed.
  final List<PriceBar> bars;

  /// Rank of the selected window's median volume within that window, 0..1.
  final double? volumePercentile;

  StockRow? rowFor(GrowthWindow window) {
    for (final row in rows) {
      if (row.window == window) return row;
    }
    return null;
  }

  List<GrowthWindow> get windows => [for (final row in rows) row.window];
}

class StockDetailScreen extends StatefulWidget {
  const StockDetailScreen({
    super.key,
    required this.market,
    required this.ticker,
    this.initialWindow,
    this.onClose,
  });

  final Market market;
  final String ticker;
  final GrowthWindow? initialWindow;

  /// Set when the screen is a pane beside a list rather than a pushed route:
  /// there is nothing to go back to, so the leading control clears the
  /// selection instead.
  final VoidCallback? onClose;

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  _DetailTab _tab = _DetailTab.overview;
  GrowthWindow? _window;
  Future<_TickerData>? _future;
  String _signature = '';

  Future<_TickerData> _load(
    MarketDatabase database,
    GrowthWindow? window,
  ) async {
    final rows = await database.ticker(widget.ticker);
    double? percentile;
    final target = window ?? (rows.isEmpty ? null : rows.first.window);
    StockRow? row;
    for (final candidate in rows) {
      if (candidate.window == target) {
        row = candidate;
        break;
      }
    }
    if (row != null) {
      percentile = await database.percentileOf(
        row.window,
        StockSort.medianVolume,
        row.medianVolume,
      );
    }
    // 52 bars at most, so the whole year is fetched once and the window pills
    // filter it without another query.
    final bars = await database.priceHistory(widget.ticker);
    return _TickerData(rows: rows, volumePercentile: percentile, bars: bars);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final database = appState.databaseOf(widget.market);
    final colors = context.colors;

    if (database == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.ticker)),
        body: StatusView(
          icon: Icons.cloud_off,
          title: '${widget.market.label} data unavailable',
          message: 'The database for this market is not loaded.',
        ),
      );
    }

    final signature =
        '${database.path}|${_window?.name}|'
        '${appState.stateOf(widget.market).asset?.syncedAt.millisecondsSinceEpoch}';
    if (signature != _signature) {
      _signature = signature;
      _future = _load(database, _window);
    }

    // A bottom navigation bar spanning a 1400px window, under a column of
    // content capped at 900, reads as a phone screen someone stretched. On a
    // desktop window the four sections sit under the header instead.
    final desktop = context.layoutSize.hasSidebar;

    return Scaffold(
      // Per screen rather than app-wide: see main.dart.
      body: SelectionArea(
        child: SafeArea(
          bottom: false,
          child: ReadableWidth(
            maxWidth: widget.onClose == null ? 900 : double.infinity,
            child: FutureBuilder<_TickerData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      _header(context, null),
                      Expanded(
                        child: StatusView(
                          icon: Icons.error_outline,
                          title: 'Could not read ${widget.ticker}',
                          message: '${snapshot.error}',
                        ),
                      ),
                    ],
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return Column(
                    children: [
                      _header(context, null),
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  );
                }
                if (data.rows.isEmpty) {
                  return Column(
                    children: [
                      _header(context, null),
                      Expanded(
                        child: StatusView(
                          icon: Icons.search_off,
                          title: '${widget.ticker} is not in this database',
                          message:
                              'It may have dropped out of the latest screener run.',
                        ),
                      ),
                    ],
                  );
                }

                final window = _resolveWindow(data);
                final row = data.rowFor(window)!;

                return Column(
                  children: [
                    _header(context, row),
                    Expanded(
                      child: PageTransitionSwitcher(
                        duration: AppMotion.contentDuration(context),
                        transitionBuilder:
                            (child, animation, secondaryAnimation) =>
                                FadeThroughTransition(
                                  animation: animation,
                                  secondaryAnimation: secondaryAnimation,
                                  fillColor: Colors.transparent,
                                  child: child,
                                ),
                        child: KeyedSubtree(
                          key: ValueKey(_tab),
                          child: switch (_tab) {
                            _DetailTab.overview => _OverviewTab(
                              data: data,
                              row: row,
                              window: window,
                              onWindowChanged: (value) =>
                                  setState(() => _window = value),
                            ),
                            _DetailTab.performance => _PerformanceTab(
                              data: data,
                            ),
                            _DetailTab.metrics => _MetricsTab(
                              data: data,
                              row: row,
                            ),
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: desktop
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.cardBorder)),
              ),
              child: NavigationBar(
                selectedIndex: _DetailTab.values.indexOf(_tab),
                onDestinationSelected: (index) =>
                    setState(() => _tab = _DetailTab.values[index]),
                destinations: [
                  for (final tab in _DetailTab.values)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      label: tab.label,
                    ),
                ],
              ),
            ),
    );
  }

  GrowthWindow _resolveWindow(_TickerData data) {
    final candidate = _window ?? widget.initialWindow;
    if (candidate != null && data.rowFor(candidate) != null) return candidate;
    return data.rows.first.window;
  }

  Widget _header(BuildContext context, StockRow? row) {
    final colors = context.colors;
    final watchlist = context.watch<WatchlistController>();
    final starred = watchlist.contains(widget.market, widget.ticker);

    return Container(
      color: colors.card,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: widget.onClose == null ? 'Back' : 'Close',
            icon: Icon(widget.onClose == null ? Icons.arrow_back : Icons.close),
            onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
          ),
          // On a desktop window the four sections live in this toolbar rather
          // than in a bottom navigation bar spanning the whole window.
          if (context.layoutSize.hasSidebar)
            Expanded(
              child: _DetailTabBar(
                selected: _tab,
                onSelected: (tab) => setState(() => _tab = tab),
              ),
            )
          else
            const Spacer(),
          IconButton(
            tooltip: starred ? 'Remove from watchlist' : 'Add to watchlist',
            icon: Icon(
              starred ? Icons.star_rounded : Icons.star_border_rounded,
              color: starred ? colors.warning : null,
            ),
            onPressed: () async {
              final added = await watchlist.toggle(
                widget.market,
                widget.ticker,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(
                    added
                        ? '${widget.ticker} added to watchlist'
                        : '${widget.ticker} removed from watchlist',
                  ),
                ),
              );
            },
          ),
          if (row?.googleFinanceUrl != null)
            GoogleFinanceButton(
              url: row!.googleFinanceUrl,
              ticker: widget.ticker,
            ),
          const InfoButton(info: PageInfos.stockDetail),
          PopupMenuButton<String>(
            onSelected: (value) => _onMenu(context, value, row),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'copy', child: Text('Copy summary')),
              if (row?.googleFinanceUrl != null)
                const PopupMenuItem(
                  value: 'copy-link',
                  child: Text('Copy Google Finance link'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    String action,
    StockRow? row,
  ) async {
    if (row == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(
          ClipboardData(
            text:
                '${row.ticker} (${row.exchange}) — ${row.name}\n'
                '${row.window.longLabel}: ${Fmt.price(row.firstPrice)} → '
                '${Fmt.price(row.latestPrice)} '
                '(${Fmt.signedPercent(row.pctChange)})\n'
                'Data as of ${Fmt.date(row.dataAsOf)}',
          ),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Summary copied')));
      case 'copy-link':
        final url = row.googleFinanceUrl;
        if (url == null) return;
        await Clipboard.setData(ClipboardData(text: url));
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Link copied')));
    }
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.data,
    required this.row,
    required this.window,
    required this.onWindowChanged,
  });

  final _TickerData data;
  final StockRow row;
  final GrowthWindow window;
  final ValueChanged<GrowthWindow> onWindowChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Prefer the published weekly bars, clipped to the window the pills select.
    // Files without price history fall back to the window endpoints.
    final from = DateTime.tryParse(row.firstDate ?? '');
    final to = DateTime.tryParse(row.lastDate ?? '');
    final windowBars = [
      for (final bar in data.bars)
        if ((from == null || !bar.date.isBefore(from)) &&
            (to == null || !bar.date.isAfter(to)))
          bar,
    ];
    final usingHistory = windowBars.length >= 2;
    final points = usingHistory
        ? ChartPoint.fromBars(windowBars)
        : ChartPoint.fromSeries(PriceSeries.build(data.rows, window));

    // With history, the headline figures come from the same bars the chart
    // draws, so the numbers and the line agree. They differ from the screener's
    // own endpoints — the window opens on a calendar date, the bars are weekly
    // closes — so the published change stays on screen beside them rather than
    // being quietly replaced.
    final firstBar = usingHistory ? windowBars.first : null;
    final lastBar = usingHistory ? windowBars.last : null;
    final shownFirstPrice = firstBar?.plotPrice ?? row.firstPrice;
    final shownLastPrice = lastBar?.plotPrice ?? row.latestPrice;
    final shownChange = shownLastPrice - shownFirstPrice;
    final shownPct = shownFirstPrice > 0
        ? (shownLastPrice / shownFirstPrice - 1) * 100
        : row.pctChange;
    final shownFirstDate = firstBar == null
        ? Fmt.dateCompact(row.firstDate)
        : Fmt.shortDate(firstBar.date);
    final shownLastDate = lastBar == null
        ? Fmt.dateCompact(row.lastDate)
        : Fmt.shortDate(lastBar.date);

    // The link for the window on screen. The file publishes one per window,
    // differing only in a `window=` parameter, so listing all five was five
    // rows pointing at the same page. Older files publish none at all.
    final link =
        row.googleFinanceUrl ??
        [
          for (final entry in data.rows)
            if (entry.googleFinanceUrl != null) entry.googleFinanceUrl,
        ].firstOrNull;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Container(
          color: colors.card,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ticker, name and listing on one line, wrapping only where the
              // row is too narrow to hold them: three stacked lines pushed
              // the price and its tiles down the screen for nothing.
              Wrap(
                spacing: 12,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    row.ticker,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    row.name,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: colors.textName,
                    ),
                  ),
                  Text(
                    '${row.exchange} · ${_prettyAssetType(row.assetType)}',
                    style: TextStyle(fontSize: 12, color: colors.textTertiary),
                  ),
                  // Published for the ASX ETFs only, so the line carries the
                  // chip only where the row is labelled.
                  if (CategoryChip.maybe(row.category) case final chip?) chip,
                ],
              ),
              const SizedBox(height: 14),
              _Quote(
                price: Fmt.price(shownLastPrice),
                window: usingHistory
                    ? '${row.window.longLabel} change, weekly closes'
                    : '${row.window.longLabel} change',
                screener: usingHistory
                    ? 'screener: ${Fmt.signedPercent(row.pctChange)}'
                    : null,
                tiles: [
                  (
                    label: 'Change',
                    value: Fmt.signedPercent(shownPct),
                    color: colors.forChange(shownPct),
                  ),
                  (
                    label: 'Price Change',
                    value: Fmt.signedPrice(shownChange),
                    color: colors.forChange(shownChange),
                  ),
                  (
                    label: 'First Price',
                    value: Fmt.price(shownFirstPrice),
                    color: null,
                  ),
                  (
                    label: 'Last Price',
                    value: Fmt.price(shownLastPrice),
                    color: null,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (row.threshold != null) ...[
          const SizedBox(height: 12),
          ScreenReason(row: row),
        ],
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
          child: Column(
            children: [
              PeriodSelector<GrowthWindow>(
                values: data.windows,
                selected: window,
                labelOf: (value) => value.label,
                onChanged: onWindowChanged,
              ),
              const SizedBox(height: 6),
              PriceChart(
                points: points,
                lineColor: colors.forChange(row.pctChange),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: Text(
                  usingHistory
                      ? '${windowBars.length} weekly closes published for this '
                            'window, plotted at their own dates. The prices and '
                            'dates above come from these bars; the screener '
                            'measures the window from ${Fmt.dateCompact(row.firstDate)} '
                            'at ${Fmt.price(row.firstPrice)}.'
                      : points.length >= 2
                      ? 'No weekly history covers this window, so the chart '
                            'falls back to the prices the window itself '
                            'publishes: its open and its close.'
                      : 'This window publishes a single price.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        MetricRow(
                          dense: true,
                          label: 'First Date',
                          value: shownFirstDate,
                        ),
                        MetricRow(
                          dense: true,
                          label: 'Last Date',
                          value: shownLastDate,
                        ),
                        MetricRow(
                          dense: true,
                          label: 'First Price',
                          value: Fmt.price(shownFirstPrice),
                        ),
                        MetricRow(
                          dense: true,
                          label: 'Last Price',
                          value: Fmt.price(shownLastPrice),
                        ),
                        MetricRow(
                          dense: true,
                          label: 'Days Cov.',
                          value: Fmt.integer(row.daysCovered),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 220, color: colors.divider),
                  Expanded(
                    child: Column(
                      children: [
                        MetricRow(
                          dense: true,
                          label: 'Obs.',
                          value: Fmt.integer(row.observations),
                        ),
                        MetricRow(
                          dense: true,
                          label: 'Coverage',
                          value: Fmt.coverage(row.coverage),
                        ),
                        MetricRow(
                          dense: true,
                          label: 'Obs. Ratio',
                          value: Fmt.coverage(row.observationRatio),
                        ),
                        MetricRow(
                          dense: true,
                          label: 'Median Vol.',
                          value: Fmt.compact(row.medianVolume),
                        ),
                        MetricRow(
                          dense: true,
                          label: 'Price Band',
                          value: row.priceBasis.isEmpty ? '—' : row.priceBasis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (link != null) ...[
          const SectionHeader(title: 'External links'),
          Panel(
            child: ListTile(
              leading: Icon(Icons.open_in_new, color: colors.interactive),
              title: Text('Google Finance · ${window.longLabel}'),
              subtitle: Text(
                link,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => openExternalUrl(context, link),
            ),
          ),
        ],
        const SectionHeader(title: 'Provenance'),
        Panel(
          child: Column(
            children: [
              MetricRow(label: 'Market file', value: row.market.objectKey),
              Divider(height: 1, color: colors.divider, indent: 14),
              MetricRow(label: 'Data as of', value: Fmt.date(row.dataAsOf)),
              Divider(height: 1, color: colors.divider, indent: 14),
              MetricRow(
                label: 'Run id',
                value: row.runId ?? '—',
                monospaceValue: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricsTab extends StatelessWidget {
  const _MetricsTab({required this.data, required this.row});

  final _TickerData data;
  final StockRow row;

  /// The weekly bars inside this row's window, if any are published.
  List<PriceBar> get _windowBars {
    final from = DateTime.tryParse(row.firstDate ?? '');
    final to = DateTime.tryParse(row.lastDate ?? '');
    return [
      for (final bar in data.bars)
        if ((from == null || !bar.date.isBefore(from)) &&
            (to == null || !bar.date.isAfter(to)))
          bar,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trend = assessTrend(data.rows);
    final percentile = data.volumePercentile;
    final bars = _windowBars;
    final weeklyPct = bars.length >= 2 && bars.first.plotPrice > 0
        ? (bars.last.plotPrice / bars.first.plotPrice - 1) * 100
        : row.pctChange;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionHeader(
          title: 'Key Metrics',
          padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: MetricCard(
                        label: 'Price Change (${row.window.label})',
                        value: Fmt.signedPrice(row.priceChange),
                        valueColor: colors.forChange(row.priceChange),
                        caption: Fmt.signedPercent(row.pctChange),
                        captionColor: colors.forChange(row.pctChange),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        label: 'Latest Price',
                        value: Fmt.price(row.latestPrice),
                        caption: row.priceBasis.isEmpty
                            ? null
                            : '${row.priceBasis} basis',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: MetricCard(
                        label: 'Median Daily Volume',
                        value: Fmt.compact(row.medianVolume),
                        badge: percentile == null
                            ? null
                            : TagBadge(
                                label: _volumeBand(percentile),
                                foreground: colors.warning,
                                background: colors.warningSurface,
                              ),
                        caption: percentile == null
                            ? null
                            : 'above ${(percentile * 100).clamp(0, 100).toStringAsFixed(0)}% in window',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        label: 'Momentum',
                        value: trend.label.label,
                        valueColor: switch (trend.label) {
                          TrendLabel.accelerating => colors.positive,
                          TrendLabel.cooling => colors.negative,
                          _ => colors.textPrimary,
                        },
                        trailing: Icon(
                          switch (trend.label) {
                            TrendLabel.accelerating => Icons.trending_up,
                            TrendLabel.cooling => Icons.trending_down,
                            _ => Icons.trending_flat,
                          },
                          size: 18,
                          color: switch (trend.label) {
                            TrendLabel.accelerating => colors.positive,
                            TrendLabel.cooling => colors.negative,
                            _ => colors.textSecondary,
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
            trend.description,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: colors.textTertiary,
            ),
          ),
        ),
        const SectionHeader(title: 'Detailed Metrics'),
        Panel(
          child: Column(
            children: [
              MetricRow(label: 'Ticker', value: row.ticker),
              _divider(colors),
              MetricRow(label: 'Exchange', value: row.exchange),
              _divider(colors),
              MetricRow(
                label: 'Asset Type',
                value: _prettyAssetType(row.assetType),
              ),
              if (row.issuer case final issuer?) ...[
                _divider(colors),
                MetricRow(label: 'Issuer', value: issuer),
              ],
              if (CategoryChip.maybe(row.category) case final chip?) ...[
                _divider(colors),
                MetricRow(label: 'Category', value: '', trailing: chip),
              ],
              _divider(colors),
              MetricRow(
                label: 'Screener first price',
                value:
                    '${Fmt.price(row.firstPrice)}'
                    ' · ${Fmt.date(row.firstDate)}',
              ),
              _divider(colors),
              MetricRow(
                label: 'Screener last price',
                value:
                    '${Fmt.price(row.latestPrice)}'
                    ' · ${Fmt.date(row.lastDate)}',
              ),
              _divider(colors),
              MetricRow(
                label: 'Screener change',
                value: Fmt.signedPercent(row.pctChange),
                valueColor: colors.forChange(row.pctChange),
              ),
              if (row.threshold case final cutOff?) ...[
                _divider(colors),
                MetricRow(
                  label: 'Screen cut-off',
                  value: Fmt.percent(cutOff, decimals: 1),
                ),
                _divider(colors),
                MetricRow(
                  label: 'Margin over cut-off',
                  value: Fmt.signedPercent(
                    row.marginOverThreshold ?? 0,
                    decimals: 1,
                  ),
                  valueColor: colors.forChange(row.marginOverThreshold ?? 0),
                ),
              ],
              if (bars.length >= 2) ...[
                _divider(colors),
                MetricRow(
                  label: 'Weekly first close',
                  value:
                      '${Fmt.price(bars.first.plotPrice)}'
                      ' · ${Fmt.date(bars.first.date.toIso8601String())}',
                ),
                _divider(colors),
                MetricRow(
                  label: 'Weekly last close',
                  value:
                      '${Fmt.price(bars.last.plotPrice)}'
                      ' · ${Fmt.date(bars.last.date.toIso8601String())}',
                ),
                _divider(colors),
                MetricRow(
                  label: 'Weekly change',
                  value: Fmt.signedPercent(weeklyPct),
                  valueColor: colors.forChange(weeklyPct),
                ),
              ],
              _divider(colors),
              MetricRow(
                label: 'Observations',
                value: Fmt.integer(row.observations),
              ),
              _divider(colors),
              MetricRow(
                label: 'Days Covered',
                value: Fmt.integer(row.daysCovered),
              ),
              _divider(colors),
              MetricRow(label: 'Coverage', value: Fmt.coverage(row.coverage)),
              _divider(colors),
              MetricRow(
                label: 'Observation Ratio',
                value: Fmt.coverage(row.observationRatio),
              ),
              _divider(colors),
              MetricRow(
                label: 'Median Volume',
                value: Fmt.integer(row.medianVolume),
              ),
              _divider(colors),
              MetricRow(
                label: 'Price Band',
                value: row.priceBasis.isEmpty ? '—' : row.priceBasis,
              ),
              _divider(colors),
              MetricRow(label: 'Data As Of', value: Fmt.date(row.dataAsOf)),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _divider(ScreenerColors colors) =>
      Divider(height: 1, color: colors.divider, indent: 14, endIndent: 14);

  static String _volumeBand(double percentile) {
    if (percentile >= 0.8) return 'High';
    if (percentile >= 0.4) return 'Moderate';
    return 'Low';
  }
}

class _PerformanceTab extends StatelessWidget {
  const _PerformanceTab({required this.data});

  final _TickerData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Older files publish no cut-off at all; the column is dropped rather than
    // filled with dashes.
    final anyThreshold = data.rows.any((row) => row.threshold != null);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionHeader(
          title: 'Every window',
          padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
        ),
        Panel(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Row(
                  children: [
                    _cell('Window', colors.textSecondary, flex: 3),
                    _cell('Open', colors.textSecondary, flex: 4, end: true),
                    _cell('Close', colors.textSecondary, flex: 4, end: true),
                    // The cut-off sits beside the change it was applied to, so
                    // the two can be read against each other.
                    if (anyThreshold)
                      _cell(
                        'Cut-off',
                        colors.textSecondary,
                        flex: 3,
                        end: true,
                      ),
                    _cell('Change', colors.textSecondary, flex: 4, end: true),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.divider),
              for (final row in data.rows) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      _cell(
                        row.window.label,
                        colors.textPrimary,
                        flex: 3,
                        bold: true,
                      ),
                      _cell(
                        Fmt.price(row.firstPrice),
                        colors.textPrimary,
                        flex: 4,
                        end: true,
                      ),
                      _cell(
                        Fmt.price(row.latestPrice),
                        colors.textPrimary,
                        flex: 4,
                        end: true,
                      ),
                      if (anyThreshold)
                        _cell(
                          row.threshold == null
                              ? '—'
                              : Fmt.percent(row.threshold!, decimals: 1),
                          colors.textSecondary,
                          flex: 3,
                          end: true,
                        ),
                      Expanded(
                        flex: 4,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ChangeChip(
                            pctChange: row.pctChange,
                            dense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (row != data.rows.last)
                  Divider(height: 1, color: colors.divider, indent: 14),
              ],
            ],
          ),
        ),
        const SectionHeader(title: 'Coverage by window'),
        Panel(
          child: Column(
            children: [
              for (final row in data.rows) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          row.window.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: row.coverage.clamp(0, 1),
                            minHeight: 6,
                            backgroundColor: colors.neutralSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          '${Fmt.integer(row.observations)} obs · '
                          '${Fmt.integer(row.daysCovered)}d',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (row != data.rows.last)
                  Divider(height: 1, color: colors.divider, indent: 14),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static Widget _cell(
    String text,
    Color color, {
    int flex = 1,
    bool end = false,
    bool bold = false,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: end ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

typedef _Stat = ({String label, String value, Color? color});

/// The price, the window it covers, and the four numbers that describe it.
///
/// Side by side where the row can hold both — a detail pane is usually wide
/// enough, and stacking them there left the headline's own line half empty.
/// Stacked below the breakpoint, where four tiles beside a price would be
/// narrower than the numbers in them.
class _Quote extends StatelessWidget {
  const _Quote({
    required this.price,
    required this.window,
    required this.screener,
    required this.tiles,
  });

  final String price;
  final String window;
  final String? screener;
  final List<_Stat> tiles;

  /// How much has to be left for the tiles, after the headline and the gap,
  /// before the two share a row.
  ///
  /// Measured against what is left rather than against the whole width: a
  /// detail pane on a 1240px window is only about 550px wide once the
  /// sidebar and the list beside it have theirs, and a threshold on the
  /// window's width stacked the quote on exactly the layout it was meant to
  /// fix. Two tiles of ~120 fit in this, and [_StatTiles] deals four across
  /// when it is given enough for them.
  static const _minTiles = 250.0;

  /// What the headline is allowed to take when they share a row, so the
  /// tiles get the rest rather than splitting it.
  static const _headlineWidth = 230.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final headline = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          price,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
            height: 1.05,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          window,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        if (screener case final line?) ...[
          const SizedBox(height: 2),
          Text(
            line,
            style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final forTiles = constraints.maxWidth - _headlineWidth - 20;
        if (forTiles < _minTiles) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              headline,
              const SizedBox(height: 14),
              _StatTiles(tiles: tiles),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _headlineWidth),
              child: headline,
            ),
            const SizedBox(width: 20),
            Expanded(child: _StatTiles(tiles: tiles)),
          ],
        );
      },
    );
  }
}

/// The four numbers under the quote, as tiles of their own.
///
/// Four across where there is room, two by two below it: at 320dp a quarter
/// of the width cuts "+1,263.5%" in half.
class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.tiles});

  final List<_Stat> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        // Four across only where four can hold the numbers at full size. The
        // widest value the files produce — "+2,454.7%", "139,225.00" — is
        // 129px as the app renders it, and the tile adds 24 of padding. Below
        // that the tiles would scale their own numbers down, which is the
        // opposite of what they are for.
        const forFour = 4 * (129 + 24) + 3 * gap;
        final columns = constraints.maxWidth >= forFour ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: width,
                child: _StatTile(tile: tile),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.tile});

  final _Stat tile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
      decoration: BoxDecoration(
        color: colors.pageBackground,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tile.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              tile.value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: tile.color ?? colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _prettyAssetType(String raw) {
  if (raw.isEmpty) return 'Unknown';
  if (raw.toLowerCase() == 'etf') return 'ETF';
  return Fmt.titleCase(raw);
}

/// The detail screen's four sections, as pills in the header toolbar.
///
/// The handset shows these in a bottom navigation bar; a desktop window has
/// the width to carry them beside the back button instead.
class _DetailTabBar extends StatelessWidget {
  const _DetailTabBar({required this.selected, required this.onSelected});

  final _DetailTab selected;
  final ValueChanged<_DetailTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) => _row(
        context,
        colors,
        // In a detail pane beside a list there is room for the icons but not
        // always for their labels, and four labels colliding with the actions
        // beside them is worse than four icons.
        labelled: constraints.maxWidth >= 460,
      ),
    );
  }

  Widget _row(
    BuildContext context,
    ScreenerColors colors, {
    required bool labelled,
  }) {
    // Scaled to fit rather than flexed: flex children share the row evenly,
    // which truncates "Overview" while "Links" still has room to spare. At
    // their natural widths the four pills fit what this toolbar gives them,
    // and the row shrinks as one if a wider font ever changes that.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 4),
          for (final tab in _DetailTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: tab == selected
                    ? colors.interactiveSurface
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                clipBehavior: Clip.antiAlias,
                child: Tooltip(
                  message: labelled ? '' : tab.label,
                  child: InkWell(
                    onTap: () => onSelected(tab),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: labelled ? 13 : 10,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            tab.icon,
                            size: 17,
                            color: tab == selected
                                ? colors.interactive
                                : colors.textSecondary,
                          ),
                          if (labelled) ...[
                            const SizedBox(width: 8),
                            Text(
                              tab.label,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: tab == selected
                                    ? colors.interactive
                                    : colors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
