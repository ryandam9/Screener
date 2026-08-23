import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../widgets/change_chip.dart';
import '../widgets/panels.dart';
import '../widgets/price_chart.dart';
import '../widgets/readable_width.dart';

enum _DetailTab {
  overview('Overview', Icons.description_outlined),
  metrics('Metrics', Icons.bar_chart_outlined),
  windows('Windows', Icons.history),
  links('Links', Icons.link);

  const _DetailTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Opens [url] in the platform browser, and says so when that is not possible.
///
/// url_launcher signals failure two different ways depending on the platform
/// and the reason: it can return false, or it can throw a PlatformException
/// (which is what happens when no application is registered for https at all).
/// Only checking the return value leaves the tap doing nothing at all, so both
/// are handled here, and the URL can still be copied when it cannot be opened.
Future<void> openExternalUrl(BuildContext context, String? url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = url == null ? null : Uri.tryParse(url);

  if (uri == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('This row has no link published')),
    );
    return;
  }

  var launched = false;
  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    launched = false;
  }
  if (launched) return;

  messenger.showSnackBar(
    SnackBar(
      content: const Text('Could not open the link'),
      action: SnackBarAction(
        label: 'Copy',
        onPressed: () => Clipboard.setData(ClipboardData(text: url!)),
      ),
    ),
  );
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
  });

  final Market market;
  final String ticker;
  final GrowthWindow? initialWindow;

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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ReadableWidth(
          maxWidth: 900,
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
                    child: switch (_tab) {
                      _DetailTab.overview => _OverviewTab(
                        data: data,
                        row: row,
                        window: window,
                        onWindowChanged: (value) =>
                            setState(() => _window = value),
                      ),
                      _DetailTab.metrics => _MetricsTab(data: data, row: row),
                      _DetailTab.windows => _WindowsTab(data: data),
                      _DetailTab.links => _LinksTab(data: data, row: row),
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.cardBorder)),
        ),
        child: NavigationBar(
          selectedIndex: _DetailTab.values.indexOf(_tab),
          onDestinationSelected: (index) =>
              setState(() => _tab = _DetailTab.values[index]),
          destinations: [
            for (final tab in _DetailTab.values)
              NavigationDestination(icon: Icon(tab.icon), label: tab.label),
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
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
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
          PopupMenuButton<String>(
            onSelected: (value) => _onMenu(context, value, row),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'copy', child: Text('Copy summary')),
              if (row?.googleFinanceUrl != null)
                const PopupMenuItem(
                  value: 'open',
                  child: Text('Open in Google Finance'),
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
      case 'open':
        await openExternalUrl(context, row.googleFinanceUrl);
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

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Container(
          color: colors.card,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 2),
              Text(
                row.name,
                style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                '${row.exchange} · ${_prettyAssetType(row.assetType)}',
                style: TextStyle(fontSize: 12, color: colors.textTertiary),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Fmt.price(shownLastPrice),
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            height: 1.05,
                            color: colors.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${Fmt.signedPrice(shownChange)} '
                          '(${Fmt.signedPercent(shownPct)})',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: colors.forChange(shownPct),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          usingHistory
                              ? '${row.window.longLabel} change, weekly closes'
                              : '${row.window.longLabel} change',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                        if (usingHistory) ...[
                          const SizedBox(height: 2),
                          Text(
                            'screener: ${Fmt.signedPercent(row.pctChange)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _MiniStat(
                        label: 'First Price',
                        value: Fmt.price(shownFirstPrice),
                      ),
                      const SizedBox(height: 10),
                      _MiniStat(
                        label: 'Last Price',
                        value: Fmt.price(shownLastPrice),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Text(
            'Data as of ${Fmt.date(row.dataAsOf)}'
            '${row.runId == null ? '' : ' · run ${row.runId}'}',
            style: TextStyle(fontSize: 11, color: colors.textTertiary),
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

class _WindowsTab extends StatelessWidget {
  const _WindowsTab({required this.data});

  final _TickerData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                      Text(
                        '${Fmt.integer(row.observations)} obs · '
                        '${Fmt.integer(row.daysCovered)}d',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.textSecondary,
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

class _LinksTab extends StatelessWidget {
  const _LinksTab({required this.data, required this.row});

  final _TickerData data;
  final StockRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionHeader(
          title: 'External links',
          padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
        ),
        Panel(
          child: Column(
            children: [
              for (final entry in data.rows)
                if (entry.googleFinanceUrl != null)
                  ListTile(
                    leading: Icon(Icons.open_in_new, color: colors.positive),
                    title: Text('Google Finance · ${entry.window.longLabel}'),
                    subtitle: Text(
                      entry.googleFinanceUrl!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () =>
                        openExternalUrl(context, entry.googleFinanceUrl),
                  ),
            ],
          ),
        ),
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

String _prettyAssetType(String raw) {
  if (raw.isEmpty) return 'Unknown';
  if (raw.toLowerCase() == 'etf') return 'ETF';
  return raw
      .split(RegExp(r'[_\s]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
