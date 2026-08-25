import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/history_ticker.dart';
import '../../models/market.dart';
import '../../models/price_bar.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../info/page_info.dart';
import '../responsive.dart';
import '../widgets/change_chip.dart';
import '../widgets/google_finance_button.dart';
import '../widgets/info_dialog.dart';
import '../widgets/panels.dart';
import '../widgets/price_chart.dart';
import '../widgets/table_frame.dart';
import '../widgets/ticker_avatar.dart';

/// How much of a ticker's history the chart shows.
enum _Span {
  month('1M', 31),
  quarter('3M', 92),
  halfYear('6M', 183),
  year('1Y', 366),
  all('All', 100000);

  const _Span(this.label, this.days);
  final String label;
  final int days;
}

/// Every ticker the run collected, not just the ones that passed a screen.
///
/// The growth tables answer "what moved"; this answers "what happened to X",
/// for any X in the market — which is only possible now that the file carries
/// the whole market's bars.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.embedded = false});

  /// Set when the desktop shell hosts this screen in its content area, where
  /// the section already has a frame and a title of its own.
  final bool embedded;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  HistoryTicker? _selected;
  bool _byChange = true;
  Market? _market;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Markets whose file carries the whole-market history. Only the ASX file
  /// does today; the page follows whatever the files publish.
  List<Market> _marketsWith(AppState appState) => [
    for (final market in Market.values)
      if (appState.databaseOf(market)?.hasMarketHistory ?? false) market,
  ];

  List<HistoryTicker> _filter(List<HistoryTicker> tickers) {
    final query = _query.trim().toLowerCase();
    final rows = [
      for (final ticker in tickers)
        if (query.isEmpty ||
            ticker.ticker.toLowerCase().contains(query) ||
            (ticker.name?.toLowerCase().contains(query) ?? false))
          ticker,
    ];
    if (!_byChange) {
      rows.sort((a, b) => a.ticker.compareTo(b.ticker));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final markets = _marketsWith(appState);
    final desktop = context.layoutSize.isDesktop;

    // Whichever market is chosen, falling back to the first that publishes
    // history: today that is the ASX, but the page follows the files rather
    // than naming a market of its own.
    final market = markets.contains(_market) ? _market! : markets.firstOrNull;

    final body = market == null
        ? const StatusView(
            icon: Icons.candlestick_chart_outlined,
            title: 'No price history published',
            message:
                'Neither file carries the whole-market history table yet. '
                'It arrives with the next run that publishes one.',
          )
        : _Body(
            database: appState.databaseOf(market)!,
            markets: markets,
            market: market,
            search: _search,
            query: _query,
            byChange: _byChange,
            selected: _selected,
            filter: _filter,
            onQuery: (value) => setState(() => _query = value),
            onSort: (value) => setState(() => _byChange = value),
            onSelect: (ticker) => setState(() => _selected = ticker),
            onMarket: (value) => setState(() {
              _market = value;
              // The selection belongs to the market it came from.
              _selected = null;
            }),
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Price history'),
        actions: const [
          InfoButton(info: PageInfos.history),
          SizedBox(width: 4),
        ],
      ),
      body: desktop ? body : SafeArea(child: body),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.database,
    required this.markets,
    required this.market,
    required this.search,
    required this.query,
    required this.byChange,
    required this.selected,
    required this.filter,
    required this.onQuery,
    required this.onSort,
    required this.onSelect,
    required this.onMarket,
  });

  final MarketDatabase database;

  /// Every market whose file publishes history; a selector appears when there
  /// is more than one.
  final List<Market> markets;
  final Market market;

  final TextEditingController search;
  final String query;
  final bool byChange;
  final HistoryTicker? selected;
  final List<HistoryTicker> Function(List<HistoryTicker>) filter;
  final ValueChanged<String> onQuery;
  final ValueChanged<bool> onSort;
  final ValueChanged<HistoryTicker> onSelect;
  final ValueChanged<Market> onMarket;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HistoryTicker>>(
      future: database.historyTickers(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StatusView(
            icon: Icons.error_outline,
            title: 'Could not read the history',
            message: '${snapshot.error}',
          );
        }
        final all = snapshot.data;
        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final rows = filter(all);

        return LayoutBuilder(
          builder: (context, constraints) {
            // Wide enough for the chart to sit beside the list; a phone opens
            // it as a page of its own instead.
            final split = constraints.maxWidth >= 900;
            final list = _TickerList(
              database: database,
              markets: markets,
              market: market,
              onMarket: onMarket,
              rows: rows,
              total: all.length,
              search: search,
              byChange: byChange,
              selected: selected,
              framed: split,
              onQuery: onQuery,
              onSort: onSort,
              onSelect: (ticker) {
                if (split) {
                  onSelect(ticker);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(ticker.ticker)),
                        body: SafeArea(
                          child: _Detail(database: database, ticker: ticker),
                        ),
                      ),
                    ),
                  );
                }
              },
            );

            if (!split) return list;

            final shown = selected ?? (rows.isEmpty ? null : rows.first);
            return Row(
              children: [
                SizedBox(
                  width: (constraints.maxWidth * 0.34).clamp(340.0, 460.0),
                  child: list,
                ),
                Container(width: 1, color: context.colors.cardBorder),
                Expanded(
                  child: shown == null
                      ? const StatusView(
                          icon: Icons.show_chart,
                          title: 'Select a ticker',
                          message: 'Its published bars are charted here.',
                        )
                      : _Detail(
                          key: ValueKey(shown.ticker),
                          database: database,
                          ticker: shown,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _TickerList extends StatelessWidget {
  const _TickerList({
    required this.database,
    required this.markets,
    required this.market,
    required this.onMarket,
    required this.rows,
    required this.total,
    required this.search,
    required this.byChange,
    required this.selected,
    required this.framed,
    required this.onQuery,
    required this.onSort,
    required this.onSelect,
  });

  final MarketDatabase database;
  final List<Market> markets;
  final Market market;
  final ValueChanged<Market> onMarket;
  final List<HistoryTicker> rows;
  final int total;
  final TextEditingController search;
  final bool byChange;
  final HistoryTicker? selected;
  final bool framed;
  final ValueChanged<String> onQuery;
  final ValueChanged<bool> onSort;
  final ValueChanged<HistoryTicker> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          // Only when there is a choice: one market publishing history needs
          // no switch, and today only the ASX file does.
          if (markets.length > 1) ...[
            PeriodSelector<Market>(
              values: markets,
              selected: market,
              labelOf: (value) => value.label,
              onChanged: onMarket,
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: onQuery,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search ${database.market.label} tickers',
                    prefixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PeriodSelector<bool>(
                values: const [true, false],
                selected: byChange,
                labelOf: (value) => value ? 'Change' : 'A–Z',
                onChanged: onSort,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );

    final body = rows.isEmpty
        ? const StatusView(
            icon: Icons.search_off,
            title: 'No ticker matches',
            message: 'Try a shorter search.',
          )
        : ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (context, _) =>
                Divider(height: 1, color: colors.divider, indent: 62),
            itemBuilder: (context, index) {
              final row = rows[index];
              return _HistoryTile(
                row: row,
                selected: row.ticker == selected?.ticker,
                onTap: () => onSelect(row),
              );
            },
          );

    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Text(
        rows.length == total
            ? '$total tickers · ${database.market.label} history'
            : '${rows.length} of $total tickers',
        style: TextStyle(fontSize: 12, color: colors.textSecondary),
      ),
    );

    if (framed) {
      return TableFrame(header: header, footer: footer, child: body);
    }
    return Column(
      children: [
        header,
        Divider(height: 1, color: colors.divider),
        Expanded(child: body),
        Divider(height: 1, color: colors.divider),
        footer,
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final HistoryTicker row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: selected ? colors.positiveSurface : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TickerAvatar(ticker: row.ticker, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      row.ticker,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    Fmt.price(row.lastPrice),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChangeChip(pctChange: row.pctChange, dense: true),
                  if (row.googleFinanceUrl != null)
                    GoogleFinanceButton(
                      url: row.googleFinanceUrl,
                      ticker: row.ticker,
                      dense: true,
                    ),
                ],
              ),
              // The name when the file publishes one; the span of bars either
              // way, which is what says how much history there is to read.
              Padding(
                padding: const EdgeInsets.only(left: 46, top: 2),
                child: Text(
                  row.name == null
                      ? '${row.bars} bars to ${Fmt.shortDate(row.lastDate)}'
                      : row.name!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chart and the numbers for one ticker.
class _Detail extends StatefulWidget {
  const _Detail({super.key, required this.database, required this.ticker});

  final MarketDatabase database;
  final HistoryTicker ticker;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  _Span _span = _Span.all;
  late Future<List<PriceBar>> _bars = widget.database.historyFor(
    widget.ticker.ticker,
  );

  @override
  void didUpdateWidget(_Detail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticker.ticker != widget.ticker.ticker) {
      _bars = widget.database.historyFor(widget.ticker.ticker);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ticker = widget.ticker;

    return FutureBuilder<List<PriceBar>>(
      future: _bars,
      builder: (context, snapshot) {
        final all = snapshot.data;
        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (all.length < 2) {
          return const StatusView(
            icon: Icons.show_chart,
            title: 'Not enough history',
            message: 'This ticker has a single published bar.',
          );
        }

        final cutoff = all.last.date.subtract(Duration(days: _span.days));
        final bars = [
          for (final bar in all)
            if (!bar.date.isBefore(cutoff)) bar,
        ];
        final shown = bars.length >= 2 ? bars : all;
        final change = shown.first.plotPrice > 0
            ? (shown.last.plotPrice / shown.first.plotPrice - 1) * 100
            : 0.0;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ticker.ticker,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        ticker.name ??
                            '${widget.database.market.label} listed',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ticker.googleFinanceUrl != null)
                  GoogleFinanceButton(
                    url: ticker.googleFinanceUrl,
                    ticker: ticker.ticker,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.price(shown.last.plotPrice),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.8,
                    height: 1.05,
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ChangeChip(pctChange: change),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${Fmt.shortDate(shown.first.date)} — '
              '${Fmt.shortDate(shown.last.date)} · ${shown.length} bars',
              style: TextStyle(fontSize: 12, color: colors.textTertiary),
            ),
            const SizedBox(height: 12),
            Panel(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
              child: Column(
                children: [
                  PeriodSelector<_Span>(
                    values: _Span.values,
                    selected: _span,
                    labelOf: (value) => value.label,
                    onChanged: (value) => setState(() => _span = value),
                  ),
                  const SizedBox(height: 6),
                  PriceChart(
                    points: ChartPoint.fromBars(shown),
                    lineColor: colors.forChange(change),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  MetricRow(
                    label: 'First close',
                    value:
                        '${Fmt.price(shown.first.plotPrice)} · '
                        '${Fmt.shortDate(shown.first.date)}',
                  ),
                  MetricRow(
                    label: 'Last close',
                    value:
                        '${Fmt.price(shown.last.plotPrice)} · '
                        '${Fmt.shortDate(shown.last.date)}',
                  ),
                  MetricRow(label: 'High', value: Fmt.price(ticker.high)),
                  MetricRow(label: 'Low', value: Fmt.price(ticker.low)),
                  MetricRow(
                    label: 'Published bars',
                    value: Fmt.integer(ticker.bars),
                  ),
                  MetricRow(
                    label: 'Median volume',
                    value: Fmt.integer(_medianVolume(shown)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  double _medianVolume(List<PriceBar> bars) {
    final volumes = [
      for (final bar in bars)
        if (bar.volume > 0) bar.volume,
    ]..sort();
    if (volumes.isEmpty) return 0;
    final middle = volumes.length ~/ 2;
    return volumes.length.isOdd
        ? volumes[middle]
        : (volumes[middle - 1] + volumes[middle]) / 2;
  }
}
