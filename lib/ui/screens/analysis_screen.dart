import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/market.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/change_chip.dart';
import '../widgets/panels.dart';
import '../widgets/stock_tile.dart';
import 'stock_detail_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// Aggregate statistics for one market's screener run.
class _AnalysisData {
  const _AnalysisData({
    required this.summary,
    required this.changes,
    required this.exchanges,
    required this.byVolume,
  });

  final MarketSummary summary;
  final List<double> changes;
  final List<({String exchange, int count})> exchanges;
  final List<StockRow> byVolume;
}

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  Future<_AnalysisData>? _future;
  String _signature = '';

  Future<_AnalysisData> _load(
    MarketDatabase database,
    GrowthWindow window,
  ) async {
    return _AnalysisData(
      summary: await database.summary(),
      changes: await database.pctChanges(window),
      exchanges: await database.exchangeBreakdown(window),
      byVolume: await database.stocks(
        window,
        const StockQuery(sort: StockSort.medianVolume, limit: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.colors;
    final market = appState.selectedMarket;
    final database = appState.databaseOf(market);
    final window = appState.availableWindows.contains(appState.selectedWindow)
        ? appState.selectedWindow
        : appState.availableWindows.first;

    if (database != null) {
      final signature =
          '${database.path}|${window.name}|'
          '${appState.stateOf(market).asset?.syncedAt.millisecondsSinceEpoch}';
      if (signature != _signature) {
        _signature = signature;
        _future = _load(database, window);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
        actions: const [
          InfoButton(info: PageInfos.analysis),
          SizedBox(width: 4),
        ],
      ),
      body: database == null
          ? StatusView(
              icon: Icons.cloud_off,
              title: '${market.label} data unavailable',
              message: 'Download the database to see its analysis.',
              actionLabel: 'Retry',
              onAction: () => appState.refresh(market, force: true),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: SegmentedButton<Market>(
                    segments: [
                      for (final value in Market.values)
                        ButtonSegment(
                          value: value,
                          label: Text('${value.label} ${value.instrumentNoun}'),
                        ),
                    ],
                    selected: {market},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        appState.selectMarket(selection.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 0),
                  child: PeriodSelector<GrowthWindow>(
                    values: appState.availableWindows,
                    selected: window,
                    labelOf: (value) => value.label,
                    onChanged: appState.selectWindow,
                  ),
                ),
                FutureBuilder<_AnalysisData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return StatusView(
                        icon: Icons.error_outline,
                        title: 'Analysis failed',
                        message: '${snapshot.error}',
                      );
                    }
                    final data = snapshot.data;
                    if (data == null) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _AnalysisBody(
                      data: data,
                      window: window,
                      market: market,
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Text(
                    'Statistics describe the instruments that passed the '
                    'screen, not the whole market.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  const _AnalysisBody({
    required this.data,
    required this.window,
    required this.market,
  });

  final _AnalysisData data;
  final GrowthWindow window;
  final Market market;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stat = data.summary.statFor(window);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Run overview'),
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
                        label: 'Instruments',
                        value: Fmt.integer(stat?.count ?? 0),
                        caption: market.instrumentNoun,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        label: 'Median change',
                        value: Fmt.signedPercent(
                          stat?.medianPctChange ?? 0,
                          decimals: 2,
                        ),
                        valueColor: colors.forChange(
                          stat?.medianPctChange ?? 0,
                        ),
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
                        label: 'Strongest',
                        value: Fmt.signedPercent(
                          stat?.maxPctChange ?? 0,
                          decimals: 1,
                        ),
                        valueColor: colors.forChange(stat?.maxPctChange ?? 0),
                        caption: data.summary.topGainer?.ticker,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        label: 'Weakest',
                        value: Fmt.signedPercent(
                          stat?.minPctChange ?? 0,
                          decimals: 1,
                        ),
                        valueColor: colors.forChange(stat?.minPctChange ?? 0),
                        caption: 'screen floor',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'Change distribution'),
        Panel(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          child: _Histogram(values: data.changes),
        ),
        const SectionHeader(title: 'Windows compared'),
        Panel(
          child: Column(
            children: [
              for (final entry in data.summary.stats) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Text(
                          entry.window.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${Fmt.integer(entry.count)} ${market.instrumentNoun}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      if (entry.count > 0)
                        ChangeChip(
                          pctChange: entry.medianPctChange,
                          dense: true,
                        )
                      else
                        Text(
                          'empty',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (entry != data.summary.stats.last)
                  Divider(height: 1, color: colors.divider, indent: 14),
              ],
            ],
          ),
        ),
        if (data.exchanges.length > 1) ...[
          const SectionHeader(title: 'By exchange'),
          Panel(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              children: [
                for (final entry in data.exchanges)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 106,
                          child: Text(
                            entry.exchange,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: data.exchanges.first.count == 0
                                  ? 0
                                  : entry.count / data.exchanges.first.count,
                              minHeight: 7,
                              backgroundColor: colors.neutralSurface,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            Fmt.integer(entry.count),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SectionHeader(title: 'Most traded'),
        Panel(
          child: Column(
            children: [
              for (final row in data.byVolume) ...[
                StockTile(
                  row: row,
                  opensTo: (_) => StockDetailScreen(
                    market: row.market,
                    ticker: row.ticker,
                    initialWindow: row.window,
                  ),
                  trailingBuilder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Fmt.compact(row.medianVolume),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'median volume',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (row != data.byVolume.last)
                  Divider(height: 1, color: colors.divider, indent: 66),
              ],
            ],
          ),
        ),
        if (data.summary.consistentCount > 0) ...[
          const SectionHeader(title: 'Consistent growers'),
          Panel(
            padding: const EdgeInsets.all(14),
            child: Text(
              '${Fmt.integer(data.summary.consistentCount)} ${market.instrumentNoun} '
              'grew in every window of this run. See the Consistent tab in '
              '${market.label} markets.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bucketed distribution of percentage changes.
class _Histogram extends StatelessWidget {
  const _Histogram({required this.values});

  final List<double> values;

  static const buckets = 10;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (values.isEmpty) {
      return const StatusView(
        icon: Icons.bar_chart,
        title: 'No rows in this window',
        compact: true,
      );
    }

    final min = values.first;
    final max = values.last;
    final span = (max - min).abs() < 1e-9 ? 1.0 : max - min;
    final counts = List<int>.filled(buckets, 0);
    for (final value in values) {
      final index = (((value - min) / span) * buckets).floor().clamp(
        0,
        buckets - 1,
      );
      counts[index]++;
    }
    final peak = counts.reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < counts.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          counts[i] == 0 ? '' : '${counts[i]}',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: colors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: peak == 0 ? 0 : (counts[i] / peak) * 82,
                          decoration: BoxDecoration(
                            color: colors.positive.withValues(
                              alpha: 0.35 + 0.65 * (counts[i] / peak),
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // All three shrink: at 320dp with large text the range and the
            // count together are wider than the chart they label.
            Flexible(
              child: Text(
                Fmt.signedPercent(min, decimals: 1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ),
            Flexible(
              child: Text(
                '${values.length} instruments',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colors.textTertiary),
              ),
            ),
            Flexible(
              child: Text(
                Fmt.signedPercent(max, decimals: 1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
