import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/market_database.dart';
import '../../models/growth_window.dart';
import '../../models/market.dart';
import '../../models/stock_row.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../../state/watchlist_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../widgets/category_chip.dart';
import '../widgets/change_chip.dart';
import '../widgets/facet_filter.dart';
import '../responsive.dart';
import '../widgets/panels.dart';
import '../widgets/screen_reason.dart';
import '../widgets/table_frame.dart';
import '../widgets/stock_tile.dart';
import '../widgets/ticker_avatar.dart';
import '../widgets/watchlist_highlight.dart';
import '../widgets/watchlist_star.dart';
import 'stock_detail_screen.dart';
import '../info/page_info.dart';
import '../widgets/info_dialog.dart';

/// The market / stock list.
///
/// The published files are growth screens — every row is a positive mover — so
/// the design's "Losers" tab would always be empty. It is replaced by
/// "Consistent", backed by the `consistent_growth_stocks` table, which is the
/// genuinely interesting cut the data supports.
enum _ListTab {
  all('All Stocks', 'All'),
  top('Top Movers', 'Movers'),
  consistent('Consistent', 'Consistent'),
  watchlist('Watchlist', 'Starred');

  const _ListTab(this.label, this.shortLabel);
  final String label;

  /// Used under 360dp, where the four full labels are clipped rather than
  /// merely tight.
  final String shortLabel;
}

class MarketListScreen extends StatefulWidget {
  const MarketListScreen({
    super.key,
    required this.market,
    this.initialWindow,
    this.initialSearch,
    this.onSelect,
    this.selected,
  });

  final Market market;
  final GrowthWindow? initialWindow;

  /// Seeds the search box, so the desktop top bar can hand a query straight to
  /// this screen.
  final String? initialSearch;

  /// Set by the desktop shell, which shows the instrument in a pane beside
  /// this list. Without it a row opens a screen of its own, which is what a
  /// handset wants.
  final ValueChanged<StockRow>? onSelect;

  /// The row the pane is showing, marked in the list.
  final StockRow? selected;

  @override
  State<MarketListScreen> createState() => _MarketListScreenState();
}

class _MarketListScreenState extends State<MarketListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: _ListTab.values.length,
    vsync: this,
  );
  late Market _market = widget.market;
  GrowthWindow? _window;

  StockSort _sort = StockSort.pctChange;
  bool _descending = true;
  String _search = '';
  String? _exchange;
  Set<String> _categories = const {};
  Set<String> _issuers = const {};
  double? _minPctChange;
  bool _searching = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _window = widget.initialWindow;
    final search = widget.initialSearch;
    if (search != null && search.isNotEmpty) {
      _search = search;
      _searching = true;
      _searchController.text = search;
    }
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Falls back to the app-wide selection when this screen was opened from the
  /// Markets tab rather than pushed with an explicit window.
  GrowthWindow _resolveWindow(AppState appState) {
    final database = appState.databaseOf(_market);
    final available = database?.availableWindows ?? GrowthWindow.values;
    final candidate = _window ?? appState.selectedWindow;
    if (available.contains(candidate)) return candidate;
    return available.isEmpty ? GrowthWindow.sevenDays : available.first;
  }

  StockQuery _query({int? limit}) => StockQuery(
    search: _search.isEmpty ? null : _search,
    exchange: _exchange,
    categories: _categories,
    issuers: _issuers,
    minPctChange: _minPctChange,
    sort: _sort,
    descending: _descending,
    limit: limit,
  );

  void _toggleSort(StockSort sort) {
    setState(() {
      if (_sort == sort) {
        _descending = !_descending;
      } else {
        _sort = sort;
        _descending = sort != StockSort.ticker && sort != StockSort.name;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colors = context.colors;
    final window = _resolveWindow(appState);
    // 320dp phones clip the full tab labels and the long title.
    final narrow = MediaQuery.sizeOf(context).width < 360;
    final desktop = context.layoutSize.isDesktop;
    final database = appState.databaseOf(_market);
    final state = appState.stateOf(_market);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        titleSpacing: Navigator.of(context).canPop() ? 0 : 16,
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search ticker or name',
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _search = value),
              )
            : InkWell(
                onTap: () => _showScopeSheet(context, appState, window),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          narrow
                              ? '${_market.label} · ${window.label}'
                              : '${_market.label} - ${window.longLabel} '
                                    'Analysis',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down, size: 22),
                    ],
                  ),
                ),
              ),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _search = '';
                _searchController.clear();
              }
            }),
          ),
          IconButton(
            tooltip: 'Filter',
            icon: Badge(
              isLabelVisible:
                  _exchange != null ||
                  _categories.isNotEmpty ||
                  _issuers.isNotEmpty ||
                  (_minPctChange ?? 0) > 0,
              backgroundColor: colors.positive,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: database == null
                ? null
                : () => _showFilterSheet(context, database, window),
          ),
          const InfoButton(info: PageInfos.markets),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: TabBar(
            controller: _tabs,
            // All four fit at handset width; scrolling would push the last
            // tab off-screen where it reads as clipped. Under 360dp they only
            // fit shortened and a point smaller.
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: narrow
                ? const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)
                : null,
            unselectedLabelStyle: narrow
                ? const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)
                : null,
            tabs: [
              for (final tab in _ListTab.values)
                Tab(text: narrow ? tab.shortLabel : tab.label),
            ],
          ),
        ),
      ),
      body: database == null
          ? _NotReady(state: state, market: _market)
          : desktop
          // On a desktop window the list is framed like the table it is:
          // headings on a band, a border, and the count in a footer strip.
          ? TableFrame(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              header: _tabs.index == _ListTab.consistent.index
                  ? const SizedBox(height: 12)
                  : _SortHeader(
                      sort: _sort,
                      descending: _descending,
                      onSort: _toggleSort,
                      framed: true,
                    ),
              footer: _ListFooter(
                database: database,
                window: window,
                query: _query(),
                sortLabel: _sortLabel(window),
                tab: _ListTab.values[_tabs.index],
                framed: true,
              ),
              child: TabBarView(
                controller: _tabs,
                children: _tabViews(database, window),
              ),
            )
          : Column(
              children: [
                if (_tabs.index != _ListTab.consistent.index)
                  _SortHeader(
                    sort: _sort,
                    descending: _descending,
                    onSort: _toggleSort,
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: _tabViews(database, window),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: database == null || desktop
          ? null
          : _ListFooter(
              database: database,
              window: window,
              query: _query(),
              sortLabel: _sortLabel(window),
              tab: _ListTab.values[_tabs.index],
            ),
    );
  }

  List<Widget> _tabViews(MarketDatabase database, GrowthWindow window) => [
    _StockList(
      database: database,
      window: window,
      query: _query(),
      emptyTitle: 'Nothing matches those filters',
      onSelect: widget.onSelect,
      selected: widget.selected,
    ),
    _StockList(
      database: database,
      window: window,
      query: _query(limit: 25),
      emptyTitle: 'No movers in this window',
      onSelect: widget.onSelect,
      selected: widget.selected,
    ),
    _ConsistentList(
      database: database,
      search: _search,
      onSelect: widget.onSelect,
      selected: widget.selected,
    ),
    _WatchlistTab(
      database: database,
      window: window,
      sort: _sort,
      descending: _descending,
      onSelect: widget.onSelect,
      selected: widget.selected,
    ),
  ];

  String _sortLabel(GrowthWindow window) {
    final name = _sort == StockSort.pctChange
        ? '${window.label} Change'
        : _sort.label;
    return 'Sorted by $name';
  }

  Future<void> _showScopeSheet(
    BuildContext context,
    AppState appState,
    GrowthWindow window,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final windows =
            appState.databaseOf(_market)?.availableWindows ??
            GrowthWindow.values;
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const SectionHeader(
                  title: 'Market',
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<Market>(
                    segments: [
                      for (final market in Market.values)
                        ButtonSegment(value: market, label: Text(market.label)),
                    ],
                    selected: {_market},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      setState(() {
                        _market = selection.first;
                        _exchange = null;
                        _categories = const {};
                        _issuers = const {};
                      });
                      appState.selectMarket(selection.first);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                ),
                const SectionHeader(
                  title: 'Analysis window',
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                ),
                for (final value in windows)
                  ListTile(
                    title: Text('${value.longLabel} analysis'),
                    trailing: value == window
                        ? Icon(Icons.check, color: context.colors.positive)
                        : null,
                    onTap: () {
                      setState(() => _window = value);
                      appState.selectWindow(value);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showFilterSheet(
    BuildContext context,
    MarketDatabase database,
    GrowthWindow window,
  ) async {
    final exchanges = await database.exchanges(window);
    // Empty for a file that publishes no such column, which leaves the
    // section out rather than showing an "All"-only row.
    final categories = await database.categories(window);
    final issuers = await database.issuers(window);
    if (!context.mounted) return;

    var exchange = _exchange;
    final selectedCategories = _categories.toSet();
    final selectedIssuers = _issuers.toSet();
    var minPct = _minPctChange ?? 0;
    var sort = _sort;
    var descending = _descending;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (builderContext, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const SectionHeader(
                      title: 'Sort by',
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final value in StockSort.values)
                            ChoiceChip(
                              label: Text(value.label),
                              selected: sort == value,
                              onSelected: (_) =>
                                  setSheetState(() => sort = value),
                            ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      value: descending,
                      title: const Text('Highest first'),
                      onChanged: (value) =>
                          setSheetState(() => descending = value),
                    ),
                    if (exchanges.length > 1) ...[
                      const SectionHeader(
                        title: 'Exchange',
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('All'),
                              selected: exchange == null,
                              onSelected: (_) =>
                                  setSheetState(() => exchange = null),
                            ),
                            for (final value in exchanges)
                              ChoiceChip(
                                label: Text(value),
                                selected: exchange == value,
                                onSelected: (_) =>
                                    setSheetState(() => exchange = value),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (categories.isNotEmpty)
                      FacetSection(
                        title: 'Category',
                        values: categories,
                        selected: selectedCategories,
                        labelOf: Fmt.titleCase,
                        onChanged: (value, on) => setSheetState(() {
                          if (on) {
                            selectedCategories.add(value);
                          } else {
                            selectedCategories.remove(value);
                          }
                        }),
                      ),
                    if (issuers.isNotEmpty)
                      FacetSection(
                        title: 'Issuer',
                        values: issuers,
                        selected: selectedIssuers,
                        onChanged: (value, on) => setSheetState(() {
                          if (on) {
                            selectedIssuers.add(value);
                          } else {
                            selectedIssuers.remove(value);
                          }
                        }),
                      ),
                    SectionHeader(
                      title:
                          'Minimum change: ${minPct <= 0 ? 'any' : Fmt.signedPercent(minPct, decimals: 0)}',
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    ),
                    Slider(
                      value: minPct.clamp(0, 200),
                      max: 200,
                      divisions: 40,
                      label: minPct <= 0
                          ? 'any'
                          : Fmt.signedPercent(minPct, decimals: 0),
                      onChanged: (value) => setSheetState(() => minPct = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _exchange = null;
                                  _categories = const {};
                                  _issuers = const {};
                                  _minPctChange = null;
                                  _sort = StockSort.pctChange;
                                  _descending = true;
                                });
                                Navigator.of(sheetContext).pop();
                              },
                              child: const Text('Reset'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _exchange = exchange;
                                  _categories = selectedCategories;
                                  _issuers = selectedIssuers;
                                  _minPctChange = minPct <= 0 ? null : minPct;
                                  _sort = sort;
                                  _descending = descending;
                                });
                                Navigator.of(sheetContext).pop();
                              },
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.sort,
    required this.descending,
    required this.onSort,
    this.framed = false,
  });

  /// Inside a [TableFrame] the band and its border come from the frame.
  final bool framed;

  final StockSort sort;
  final bool descending;
  final ValueChanged<StockSort> onSort;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget label(String text, StockSort value, {bool end = false}) {
      final active = sort == value;
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: end
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Scaled down rather than ellipsized: "Chan…" over a column of
          // numbers says nothing, and these headings are one word each.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: end ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ),
          ),
          if (active)
            Icon(
              descending ? Icons.arrow_downward : Icons.arrow_upward,
              size: 12,
              color: colors.textPrimary,
            ),
        ],
      );
    }

    // Mirrors StockTile's geometry so each heading sits over its own column.
    //
    // Fixed columns rather than flex ones: giving each heading a Flexible split
    // the row's spare width four ways, and the slack the loose children left
    // behind was stranded rather than pushing the numbers to the right edge —
    // so "Price" and "Change" sat well to the left of the values under them.
    final dense = context.watch<SettingsController>().compactRows;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: framed
          ? null
          : BoxDecoration(
              color: colors.card,
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The rows drop their price column when the name would be squeezed;
          // the heading has to go with it or it sits over the wrong values.
          final showPrice =
              StockTile.nameSpace(
                context,
                constraints.maxWidth + 32,
                dense: dense,
              ) >=
              96;
          Widget column(double width, Widget child) => SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: child,
            ),
          );

          return Row(
            children: [
              SizedBox(width: StockTile.leadingColumn(dense: dense)),
              Expanded(
                child: InkWell(
                  onTap: () => onSort(StockSort.ticker),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: label('Ticker', StockSort.ticker),
                  ),
                ),
              ),
              const SizedBox(width: StockTile.columnGap),
              if (showPrice) ...[
                InkWell(
                  onTap: () => onSort(StockSort.latestPrice),
                  child: column(
                    StockTile.priceColumn(context),
                    label('Price', StockSort.latestPrice, end: true),
                  ),
                ),
                const SizedBox(width: StockTile.columnGap),
              ],
              InkWell(
                onTap: () => onSort(StockSort.pctChange),
                child: column(
                  StockTile.changeColumn(context),
                  // Just "Change": the window is already named in the title
                  // bar, and "7D Change" plus a sort arrow does not fit here.
                  label('Change', StockSort.pctChange, end: true),
                ),
              ),
              // The star and link at the end of every row, so the headings stay
              // over the columns they sort.
              const SizedBox(width: StockTile.actionsWidth),
            ],
          );
        },
      ),
    );
  }
}

class _StockList extends StatelessWidget {
  const _StockList({
    required this.database,
    required this.window,
    required this.query,
    required this.emptyTitle,
    this.onSelect,
    this.selected,
  });

  final MarketDatabase database;
  final GrowthWindow window;
  final StockQuery query;
  final String emptyTitle;
  final ValueChanged<StockRow>? onSelect;
  final StockRow? selected;

  @override
  Widget build(BuildContext context) {
    final dense = context.watch<SettingsController>().compactRows;
    return FutureBuilder<List<StockRow>>(
      future: database.stocks(window, query),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return StatusView(
            icon: Icons.error_outline,
            title: 'Query failed',
            message: '${snapshot.error}',
          );
        }
        final rows = snapshot.data;
        if (rows == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows.isEmpty) {
          return StatusView(
            icon: Icons.search_off,
            title: emptyTitle,
            message: 'Try clearing the search or filters.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: rows.length,
          separatorBuilder: (context, _) =>
              Divider(height: 1, color: context.colors.divider, indent: 66),
          itemBuilder: (context, index) {
            final row = rows[index];
            final select = onSelect;
            return StockTile(
              row: row,
              dense: dense,
              selected: row.key == selected?.key,
              onTap: select == null ? null : () => select(row),
              opensTo: select != null
                  ? null
                  : (_) => StockDetailScreen(
                      market: row.market,
                      ticker: row.ticker,
                      initialWindow: window,
                    ),
            );
          },
        );
      },
    );
  }
}

class _ConsistentList extends StatelessWidget {
  const _ConsistentList({
    required this.database,
    required this.search,
    this.onSelect,
    this.selected,
  });

  final MarketDatabase database;
  final String search;

  /// Where a tapped row goes. Given one — the desktop shell's detail pane —
  /// the row is handed over instead of a route being pushed over the list.
  final ValueChanged<StockRow>? onSelect;
  final StockRow? selected;

  /// Resolves a consistent grower to the row the rest of the app passes
  /// around, so the detail pane opens on it like any other list's row.
  ///
  /// Consistent growers are in every window by definition, so the shortest
  /// one always has them — but a file can be replaced between the query and
  /// the tap, and a missing row falls back to the pushed screen.
  Future<StockRow?> _rowFor(ConsistentStock stock) async {
    final windows = database.availableWindows;
    if (windows.isEmpty) return null;
    final rows = await database.stocks(
      windows.first,
      StockQuery(tickers: [stock.ticker]),
    );
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FutureBuilder<List<ConsistentStock>>(
      future: database.consistent(search: search),
      builder: (context, snapshot) {
        final rows = snapshot.data;
        if (snapshot.hasError) {
          return StatusView(
            icon: Icons.error_outline,
            title: 'Query failed',
            message: '${snapshot.error}',
          );
        }
        if (rows == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (rows.isEmpty) {
          return StatusView(
            icon: Icons.workspace_premium_outlined,
            title: database.hasConsistentTable
                ? 'No consistent growers'
                : 'Not published for this market',
            message: database.hasConsistentTable
                ? '${database.market.label} has no tickers that grew across every window in this run.'
                : 'This database has no consistent_growth_stocks table.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: rows.length,
          separatorBuilder: (context, _) =>
              Divider(height: 1, color: colors.divider, indent: 66),
          itemBuilder: (context, index) {
            final row = rows[index];
            final select = onSelect;
            void open() {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StockDetailScreen(
                    market: row.market,
                    ticker: row.ticker,
                  ),
                ),
              );
            }

            return Material(
              // Consistent growers are the one list that showed a ticker
              // without saying whether it was starred, and without a way to
              // star it. Both belong here as much as anywhere else.
              color:
                  starredRowColor(
                    context,
                    row.market,
                    row.ticker,
                    selected:
                        row.ticker == selected?.ticker &&
                        row.market == selected?.market,
                  ) ??
                  Colors.transparent,
              child: InkWell(
                onTap: select == null
                    ? open
                    : () async {
                        final resolved = await _rowFor(row);
                        if (resolved != null) {
                          select(resolved);
                        } else if (context.mounted) {
                          open();
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      TickerAvatar(ticker: row.ticker),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              row.ticker,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 1),
                            // Wrapped, as in the other lists: the name is the
                            // point of the row.
                            // See _NameLine in stock_tile.dart for why this
                            // wraps rather than flexing.
                            Wrap(
                              spacing: 6,
                              runSpacing: 3,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  row.shortName,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.25,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textName,
                                  ),
                                ),
                                if (CategoryChip.maybe(row.category)
                                    case final chip?)
                                  chip,
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ChangeChip(pctChange: row.pctChangeShortestWindow),
                            const SizedBox(height: 3),
                            Text(
                              row.thresholdShortestWindow == null
                                  ? 'shortest window'
                                  : 'shortest window · '
                                        '${Fmt.percent(row.thresholdShortestWindow!, decimals: 1)}',
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
                      WatchlistStar(
                        market: row.market,
                        ticker: row.ticker,
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _WatchlistTab extends StatelessWidget {
  const _WatchlistTab({
    required this.database,
    required this.window,
    required this.sort,
    required this.descending,
    this.onSelect,
    this.selected,
  });

  final MarketDatabase database;
  final GrowthWindow window;
  final StockSort sort;
  final bool descending;
  final ValueChanged<StockRow>? onSelect;
  final StockRow? selected;

  @override
  Widget build(BuildContext context) {
    final watchlist = context.watch<WatchlistController>();
    final tickers = watchlist.tickersFor(database.market);

    if (tickers.isEmpty) {
      return StatusView(
        icon: Icons.star_border_rounded,
        title: 'Nothing on the watchlist',
        message:
            'Star a ${database.market.label} ticker from its detail screen to track it here.',
      );
    }

    return _StockList(
      database: database,
      window: window,
      query: StockQuery(tickers: tickers, sort: sort, descending: descending),
      emptyTitle: 'Watchlisted tickers are not in this window',
      onSelect: onSelect,
      selected: selected,
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.database,
    required this.window,
    required this.query,
    required this.sortLabel,
    required this.tab,
    this.framed = false,
  });

  /// Inside a [TableFrame] the strip and its border come from the frame.
  final bool framed;

  final MarketDatabase database;
  final GrowthWindow window;
  final StockQuery query;
  final String sortLabel;
  final _ListTab tab;

  Future<(int, double?)> _countAndCutOff() async {
    final count = tab == _ListTab.consistent
        ? await database.consistentCount()
        : await database.count(window, query);
    final cutOff = tab == _ListTab.consistent
        ? null
        : await database.threshold(window);
    return (count, cutOff);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: framed ? 10 : 10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: framed
          ? null
          : BoxDecoration(
              color: colors.card,
              border: Border(top: BorderSide(color: colors.cardBorder)),
            ),
      child: Row(
        children: [
          Expanded(
            // The count and the rule that produced it, together: every row in
            // the list is here because it cleared this window's cut-off.
            child: FutureBuilder<(int, double?)>(
              future: _countAndCutOff(),
              builder: (context, snapshot) {
                final result = snapshot.data;
                final noun = tab == _ListTab.consistent
                    ? 'consistent'
                    : database.market.instrumentNoun;
                final cutOff = tab == _ListTab.consistent
                    ? null
                    : screenCutOffLabel(result?.$2);
                return Text(
                  result == null
                      ? '—'
                      : '${Fmt.integer(result.$1)} $noun'
                            '${cutOff == null ? '' : ' · $cutOff'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          // Both halves shrink: at 320dp "107 stocks" and "Sorted by 7D
          // Change" together are wider than the bar.
          Flexible(
            child: Text(
              tab == _ListTab.consistent
                  ? 'Sorted by shortest window'
                  : sortLabel,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotReady extends StatelessWidget {
  const _NotReady({required this.state, required this.market});

  final MarketState state;
  final Market market;

  @override
  Widget build(BuildContext context) {
    if (state.isBusy) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: state.progress),
            const SizedBox(height: 16),
            Text(
              'Fetching ${market.objectKey}…',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ],
        ),
      );
    }
    return StatusView(
      icon: Icons.cloud_off,
      title: '${market.label} data unavailable',
      message: state.error ?? 'The database has not been downloaded yet.',
      actionLabel: 'Try again',
      onAction: () => context.read<AppState>().refresh(market, force: true),
    );
  }
}
