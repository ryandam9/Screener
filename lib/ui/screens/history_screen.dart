import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/facets.dart';
import '../../models/history_ticker.dart';
import '../../models/market.dart';
import '../../models/price_bar.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../info/page_info.dart';
import '../responsive.dart';
import '../widgets/category_chip.dart';
import '../widgets/change_chip.dart';
import '../widgets/facet_filter.dart';
import '../widgets/google_finance_button.dart';
import '../widgets/info_dialog.dart';
import '../widgets/panels.dart';
import '../widgets/price_chart.dart';
import '../widgets/stock_tile.dart';
import '../widgets/table_frame.dart';
import '../widgets/ticker_avatar.dart';
import '../widgets/watchlist_highlight.dart';
import '../widgets/watchlist_star.dart';

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
  FacetSelection _facets = const FacetSelection();
  HistoryTicker? _selected;
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

  /// The tickers matching the search and the chosen facets, in the order the
  /// file published them — strongest first.
  ///
  /// Filtered in Dart rather than in SQL: the whole history is already read
  /// and folded per ticker for the summaries, so this is a walk over a list
  /// of a few hundred that is in memory either way.
  List<HistoryTicker> _filter(List<HistoryTicker> tickers) {
    final query = _query.trim().toLowerCase();
    return [
      for (final ticker in tickers)
        if ((query.isEmpty ||
                ticker.ticker.toLowerCase().contains(query) ||
                (ticker.name?.toLowerCase().contains(query) ?? false)) &&
            _matchesFacets(ticker))
          ticker,
    ];
  }

  /// A ticker the file publishes but never labelled carries [kMiscLabel]
  /// rather than nothing, so the 75 uncategorised ASX tickers stay reachable
  /// through the chip of that name.
  bool _matchesFacets(HistoryTicker ticker) {
    if (_facets.categories.isNotEmpty &&
        !_facets.categories.contains(ticker.category)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final markets = _marketsWith(appState);
    final desktop = context.layoutSize.hasSidebar;

    // Follow the app's selected market on first open. If that file does not
    // publish history, fall back to the first one that does.
    final preferredMarket = _market ?? appState.selectedMarket;
    final market = markets.contains(preferredMarket)
        ? preferredMarket
        : markets.firstOrNull;

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
            facets: _facets,
            selected: _selected,
            filter: _filter,
            onQuery: (value) => setState(() => _query = value),
            onFacets: (value) => setState(() => _facets = value),
            onSelect: (ticker) => setState(() => _selected = ticker),
            onMarket: (value) {
              appState.selectMarket(value);
              setState(() {
                _market = value;
                // The selection and the facets both belong to the market they
                // came from: another file labels its funds differently, if at
                // all.
                _selected = null;
                _facets = const FacetSelection();
              });
            },
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          market == null ? 'Price History' : '${market.label} Price History',
        ),
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
    required this.facets,
    required this.selected,
    required this.filter,
    required this.onQuery,
    required this.onFacets,
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
  final FacetSelection facets;
  final HistoryTicker? selected;
  final List<HistoryTicker> Function(List<HistoryTicker>) filter;
  final ValueChanged<String> onQuery;
  final ValueChanged<FacetSelection> onFacets;
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
              all: all,
              search: search,
              facets: facets,
              selected: selected,
              framed: split,
              onQuery: onQuery,
              onFacets: onFacets,
              onSelect: (ticker) {
                if (split) {
                  onSelect(ticker);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: Text(
                            '${ticker.ticker} · ${database.market.label}',
                          ),
                        ),
                        body: SafeArea(
                          bottom: false,
                          child: _Detail(
                            database: database,
                            ticker: ticker,
                            showFooterAction: false,
                          ),
                        ),
                        // Pinned rather than scrolled to: on a phone this is
                        // the one control you reach for without reading the
                        // page first, so it sits where a thumb already is.
                        bottomNavigationBar: ticker.googleFinanceUrl == null
                            ? null
                            : SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    16,
                                    12,
                                  ),
                                  child: _GoogleFinanceAction(ticker: ticker),
                                ),
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
    required this.all,
    required this.search,
    required this.facets,
    required this.selected,
    required this.framed,
    required this.onQuery,
    required this.onFacets,
    required this.onSelect,
  });

  final MarketDatabase database;
  final List<Market> markets;
  final Market market;
  final ValueChanged<Market> onMarket;
  final List<HistoryTicker> rows;
  final int total;

  /// Every ticker the file publishes, filtered or not: the chips are built
  /// from the whole set, so narrowing to one category does not then hide
  /// every other category's chip.
  final List<HistoryTicker> all;

  final TextEditingController search;
  final FacetSelection facets;
  final HistoryTicker? selected;
  final bool framed;
  final ValueChanged<String> onQuery;
  final ValueChanged<FacetSelection> onFacets;
  final ValueChanged<HistoryTicker> onSelect;

  /// The distinct values of one label across the file, alphabetically, with
  /// the catch-all last where the file has one.
  List<String> _valuesOf(String? Function(HistoryTicker) of) {
    final values = <String>{
      for (final row in all)
        if (of(row) case final value?) value,
    };
    final misc = values.remove(kMiscLabel);
    return [...values.toList()..sort(), if (misc) kMiscLabel];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final categories = _valuesOf((row) => row.category);

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
              // Beside the search box rather than in the app bar: the desktop
              // shell embeds this page without one, and the control has to
              // reach both layouts.
              if (categories.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Filter',
                  icon: Badge(
                    isLabelVisible: facets.isNotEmpty,
                    label: facets.isEmpty ? null : Text('${facets.length}'),
                    backgroundColor: colors.interactive,
                    child: const Icon(Icons.filter_list),
                  ),
                  onPressed: () async {
                    final chosen = await showFacetFilterSheet(
                      context,
                      categories: categories,
                      selection: facets,
                    );
                    if (chosen != null) onFacets(chosen);
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );

    final body = rows.isEmpty
        ? StatusView(
            icon: Icons.search_off,
            title: 'No ticker matches',
            message: facets.isEmpty
                ? 'Try a shorter search.'
                : 'No ticker matches both the search and the chosen '
                      'categories.',
          )
        : ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (context, _) =>
                Divider(height: 1, color: colors.divider, indent: 62),
            itemBuilder: (context, index) {
              final row = rows[index];
              return _HistoryTile(
                market: database.market,
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
    required this.market,
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final Market market;
  final HistoryTicker row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color:
          starredRowColor(context, market, row.ticker, selected: selected) ??
          Colors.transparent,
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
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // The price and the change travel together, right up against
                  // the star, and scale down rather than overflow: at 320dp
                  // with the largest text they are wider than what is left of
                  // the row once the avatar, the star and the link are placed.
                  // Everywhere else there is slack, so nothing is scaled.
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            Fmt.price(row.lastPrice),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ChangeChip(pctChange: row.pctChange, dense: true),
                        ],
                      ),
                    ),
                  ),
                  WatchlistStar(
                    market: market,
                    ticker: row.ticker,
                    dense: true,
                  ),
                  // The link's slot is held even when a row has no URL, so the
                  // stars stay in one column down the list rather than sliding
                  // right on the rows the file gave no exchange code.
                  if (row.googleFinanceUrl != null)
                    GoogleFinanceButton(
                      url: row.googleFinanceUrl,
                      ticker: row.ticker,
                      dense: true,
                    )
                  else
                    SizedBox(width: StockTile.actionWidth(context)),
                ],
              ),
              // The name when the file publishes one; the span of bars either
              // way, which is what says how much history there is to read.
              Padding(
                padding: const EdgeInsets.only(left: 46, top: 2),
                // Wrapped, not a Row: see _NameLine in stock_tile.dart for
                // why a Flexible name cannot save a row from a chip that is
                // wider than the line.
                child: Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      row.name == null
                          ? '${row.bars} bars to ${Fmt.shortDate(row.lastDate)}'
                          : row.name!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        // Only a real name is content; the bar count in its
                        // place is chrome and stays secondary.
                        fontWeight: row.name == null
                            ? FontWeight.w400
                            : FontWeight.w500,
                        color: row.name == null
                            ? colors.textSecondary
                            : colors.textName,
                      ),
                    ),
                    if (CategoryChip.maybe(row.category, dense: true)
                        case final chip?)
                      chip,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full-width action that opens the ticker on Google Finance.
///
/// A 26px icon in the header is a mouse target; on a phone the same link has
/// to be reachable with a thumb, which means the bottom of the screen and a
/// target the width of the page.
class _GoogleFinanceAction extends StatelessWidget {
  const _GoogleFinanceAction({required this.ticker});

  final HistoryTicker ticker;

  @override
  Widget build(BuildContext context) {
    final url = ticker.googleFinanceUrl;
    if (url == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => openExternalUrl(context, url),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text('${ticker.ticker} on Google Finance'),
        style: FilledButton.styleFrom(
          backgroundColor: context.colors.interactive,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// The chart and the numbers for one ticker.
class _Detail extends StatefulWidget {
  const _Detail({
    super.key,
    required this.database,
    required this.ticker,
    this.showFooterAction = true,
  });

  final MarketDatabase database;
  final HistoryTicker ticker;

  /// False where the page pins the action to the bottom of the window
  /// instead, so a phone does not get the same button twice.
  final bool showFooterAction;

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

        // Per screen rather than app-wide: see main.dart.
        return SelectionArea(
          child: ListView(
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
                            fontWeight: ticker.name == null
                                ? FontWeight.w400
                                : FontWeight.w500,
                            color: ticker.name == null
                                ? colors.textSecondary
                                : colors.textName,
                          ),
                        ),
                        // Only where the file labels the ticker, which is
                        // most but not all of the ASX universe.
                        if (ticker.issuer != null || ticker.category != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (ticker.issuer case final issuer?)
                                  Flexible(
                                    child: Text(
                                      issuer,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: colors.textTertiary,
                                      ),
                                    ),
                                  ),
                                if (CategoryChip.maybe(ticker.category)
                                    case final chip?) ...[
                                  if (ticker.issuer != null)
                                    const SizedBox(width: 6),
                                  chip,
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Starred from the chart as well as from the list: this is
                  // the view you reach before deciding a ticker is worth
                  // keeping, so the star has to be here too.
                  WatchlistStar(
                    market: widget.database.market,
                    ticker: ticker.ticker,
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
                  // 30px of price beside the chip is wider than a 320dp phone
                  // at the largest text sizes; the headline gives way there
                  // rather than pushing the change off the screen.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
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
              if (widget.showFooterAction) ...[
                const SizedBox(height: 16),
                _GoogleFinanceAction(ticker: ticker),
              ],
            ],
          ),
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
