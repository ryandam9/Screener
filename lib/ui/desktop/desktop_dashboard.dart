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
import '../widgets/google_finance_button.dart';
import '../widgets/info_dialog.dart';
import '../widgets/watchlist_star.dart';

/// Everything the desktop dashboard shows, gathered in one pass.
class DesktopDashboardData {
  const DesktopDashboardData({
    required this.topGainers,
    required this.gainersByMarket,
    required this.summaries,
    required this.movers,
    required this.runs,
  });

  /// The strongest rows of the window, every market ranked together.
  final List<StockRow> topGainers;

  /// The same ranking, per market. One market's screen regularly outruns the
  /// other's — a 40% week is ordinary in US small caps and exceptional on the
  /// ASX — so a merged top eight can be all one market. This is what the
  /// table's filter shows instead of an empty result.
  final Map<Market, List<StockRow>> gainersByMarket;
  final Map<Market, MarketSummary> summaries;
  final List<StockRow> movers;
  final List<RunInfo> runs;

  /// True when the files produced nothing to show.
  bool get isEmpty => topGainers.isEmpty && movers.isEmpty && runs.isEmpty;
}

class DesktopDashboard extends StatefulWidget {
  const DesktopDashboard({
    super.key,
    this.onSearchSubmitted,
    this.onViewAllGainers,
    this.searchFocus,
  });

  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onViewAllGainers;

  /// Held by the shell, so Ctrl+F can put the caret in the search box from
  /// anywhere in the app.
  final FocusNode? searchFocus;

  @override
  State<DesktopDashboard> createState() => _DesktopDashboardState();
}

class _DesktopDashboardState extends State<DesktopDashboard> {
  final TextEditingController _search = TextEditingController();
  FocusNode? _ownFocus;
  Future<DesktopDashboardData>? _future;
  String _signature = '';

  /// Which market the gainers table is showing, or null for both ranked
  /// together.
  Market? _gainerMarket;

  /// The security charted below the table. Defaults to the strongest mover
  /// and follows whichever row is clicked.
  StockRow? _selected;

  FocusNode get _searchFocus =>
      widget.searchFocus ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _search.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  /// The rows the gainers table is showing under the current filter.
  List<StockRow> _gainers(DesktopDashboardData data) => _gainerMarket == null
      ? data.topGainers
      : data.gainersByMarket[_gainerMarket] ?? const [];

  Future<DesktopDashboardData> _load(AppState appState) async {
    final window = appState.selectedWindow;
    final gainers = <StockRow>[];
    final movers = <StockRow>[];
    final runs = <RunInfo>[];
    final summaries = <Market, MarketSummary>{};

    for (final market in Market.values) {
      final database = appState.databaseOf(market);
      if (database == null) continue;

      runs.addAll(await database.allRuns());
      summaries[market] = await database.summary();

      if (database.availableWindows.contains(window)) {
        gainers.addAll(
          await database.stocks(window, const StockQuery(limit: 8)),
        );
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
      topGainers: gainers.take(8).toList(),
      gainersByMarket: {
        for (final market in Market.values)
          market: [
            for (final row in gainers)
              if (row.market == market) row,
          ].take(8).toList(),
      },
      summaries: summaries,
      movers: movers.take(5).toList(),
      runs: runs,
    );
  }

  /// The selection survives a reload when the ticker is still listed;
  /// otherwise it falls back to the strongest mover.
  StockRow? _resolveSelection(List<StockRow> rows) {
    if (rows.isEmpty) return null;
    final current = _selected;
    if (current != null) {
      for (final row in rows) {
        if (row.ticker == current.ticker && row.market == current.market) {
          return row;
        }
      }
    }
    return rows.first;
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
      _future = _load(appState);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          controller: _search,
          focusNode: _searchFocus,
          onSubmitted: widget.onSearchSubmitted,
        ),
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
              if (data == null || data.isEmpty) {
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
              // Keep the selection valid across reloads, window changes and
              // the market filter.
              final gainers = _gainers(data);
              final selected = _resolveSelection(gainers);
              if (selected == null) {
                return const Center(child: Text('No rows in this window'));
              }
              return _DashboardBody(
                data: data,
                gainers: gainers,
                gainerMarket: _gainerMarket,
                onGainerMarket: (market) =>
                    setState(() => _gainerMarket = market),
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

/// The bar across the top of the dashboard: what you are looking at, a search
/// box, and the controls that act on the whole page.
///
/// It used to be a single cluster of controls centred in an otherwise empty
/// strip. Naming the section on the left and pinning the controls to the right
/// gives the bar two ends to hold onto, and hands the width in between to the
/// search box.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appState = context.watch<AppState>();

    return Container(
      color: colors.card,
      padding: const EdgeInsets.fromLTRB(24, 13, 18, 13),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                // Named rather than counted: the reader wants to know which
                // screens are in front of them, and the list is short enough
                // to say. It grows with the enum.
                '${[for (final market in Market.values) market.label].join(', ')} '
                'growth screens',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                // Wide, but not the full width of a 2560px monitor: past this
                // the field is longer than anything typed into it.
                constraints: const BoxConstraints(maxWidth: 760),
                child: _SearchField(
                  controller: controller,
                  focusNode: focusNode,
                  onSubmitted: onSubmitted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          _WindowDropdown(appState: appState),
          const SizedBox(width: 10),
          _SyncButton(appState: appState),
          const SizedBox(width: 4),
          // The desktop dashboard draws its own top bar, so it needs its own
          // info button; every other section keeps the one in its app bar.
          const InfoButton(info: PageInfos.dashboard, dense: true),
        ],
      ),
    );
  }
}

/// The app's search box: submits into Markets, filtered.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14.5),
        onSubmitted: (text) {
          if (text.trim().isNotEmpty) onSubmitted?.call(text.trim());
        },
        decoration: InputDecoration(
          hintText: 'Search stocks, ETFs, or analyses…',
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: value.text.isEmpty
              // The shortcut is only worth showing while it is the thing to
              // do; once there is text, the same slot clears it.
              ? const _ShortcutHint(label: 'Ctrl F')
              : IconButton(
                  tooltip: 'Clear the search',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: colors.textSecondary,
                  onPressed: controller.clear,
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 56),
        ),
      ),
    );
  }
}

/// A keycap-style hint, the way desktop applications label their search box.
class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textTertiary,
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
    required this.gainers,
    required this.gainerMarket,
    required this.onGainerMarket,
    required this.window,
    required this.selected,
    required this.onSelect,
    required this.onOpenStock,
    this.onViewAllGainers,
  });

  final DesktopDashboardData data;

  /// The gainers to table, already filtered by [gainerMarket].
  final List<StockRow> gainers;
  final Market? gainerMarket;
  final ValueChanged<Market?> onGainerMarket;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final splitWorkspace = constraints.maxWidth >= 1020;
          final splitSupporting = constraints.maxWidth >= 820;

          final gainersPanel = DesktopPanel(
            title: 'Top Gainers (${window.longLabel})',
            leadingAction: PeriodSelector<Market?>(
              compact: true,
              values: [null, ...Market.values],
              selected: gainerMarket,
              labelOf: (market) => market?.label ?? 'Both',
              onChanged: onGainerMarket,
            ),
            actionLabel: 'View all',
            onAction: onViewAllGainers,
            child: GainersTable(
              rows: gainers,
              selected: selected,
              onTap: onSelect,
            ),
          );
          final chart = _SecurityChart(
            row: selected,
            onOpenDetails: () => onOpenStock(selected),
          );
          final recent = DesktopPanel(
            title: 'Recent Analyses',
            child: Column(
              children: [
                for (final run in data.runs.take(5)) ...[
                  _RunRow(run: run),
                  if (run != data.runs.take(5).last)
                    Divider(height: 1, color: colors.divider, indent: 18),
                ],
              ],
            ),
          );
          final movers = DesktopPanel(
            title: 'Top Movers (shortest window)',
            child: Column(
              children: [
                for (final row in data.movers) ...[
                  _MoverRow(row: row, onTap: () => onOpenStock(row)),
                  if (row != data.movers.last)
                    Divider(height: 1, color: colors.divider, indent: 18),
                ],
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MarketPulseStrip(
                summaries: data.summaries,
                window: window,
                selected: gainerMarket,
                onSelect: onGainerMarket,
              ),
              const SizedBox(height: 18),
              if (splitWorkspace)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 58, child: gainersPanel),
                    const SizedBox(width: 18),
                    Expanded(flex: 42, child: chart),
                  ],
                )
              else ...[
                gainersPanel,
                const SizedBox(height: 18),
                chart,
              ],
              const SizedBox(height: 18),
              if (splitSupporting)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: recent),
                    const SizedBox(width: 18),
                    Expanded(child: movers),
                  ],
                )
              else ...[
                recent,
                const SizedBox(height: 18),
                movers,
              ],
              const SizedBox(height: 18),
              Text(
                'Screener output, not live quotes. Prices are the window '
                'endpoints published by the pipeline.',
                style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A compact cross-market pulse. It keeps all three markets visible without
/// pushing the ranked workspace below a stack of summary cards.
class _MarketPulseStrip extends StatelessWidget {
  const _MarketPulseStrip({
    required this.summaries,
    required this.window,
    required this.selected,
    required this.onSelect,
  });

  final Map<Market, MarketSummary> summaries;
  final GrowthWindow window;
  final Market? selected;
  final ValueChanged<Market?> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var index = 0; index < Market.values.length; index++) ...[
            if (index > 0)
              Container(width: 1, height: 54, color: colors.divider),
            Expanded(
              child: _MarketPulseCell(
                market: Market.values[index],
                stat: summaries[Market.values[index]]?.statFor(window),
                selected: selected == Market.values[index],
                onTap: () => onSelect(
                  selected == Market.values[index]
                      ? null
                      : Market.values[index],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarketPulseCell extends StatelessWidget {
  const _MarketPulseCell({
    required this.market,
    required this.stat,
    required this.selected,
    required this.onTap,
  });

  final Market market;
  final WindowStat? stat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = stat?.medianPctChange;
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        color: selected ? colors.interactiveSurface : Colors.transparent,
        child: Row(
          children: [
            Text(market.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    market.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? colors.interactive
                          : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null
                        ? 'No ${window.label} rows'
                        : '${Fmt.signedPercent(value)} median',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: value == null
                          ? colors.textTertiary
                          : colors.forChange(value),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      leadingAction: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WatchlistStar(market: row.market, ticker: row.ticker),
          if (row.googleFinanceUrl != null)
            GoogleFinanceButton(url: row.googleFinanceUrl, ticker: row.ticker),
        ],
      ),
      actionLabel: 'Open details',
      onAction: onOpenDetails,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.market.money(row.latestPrice),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: row.pctChange >= 0
                          ? colors.positiveSurface
                          : colors.negativeSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      Fmt.signedPercent(row.pctChange),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.forChange(row.pctChange),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FutureBuilder<List<PriceBar>>(
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

                // The whole published year, not the table's window: a
                // seven-day window holds two weekly closes, which is a line
                // rather than a history, and this panel exists to show the
                // security itself.
                final plotted = bars;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PriceChart(
                      points: ChartPoint.fromBars(plotted),
                      lineColor: colors.forChange(row.pctChange),
                      height: 208,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: Text(
                        plotted.isEmpty
                            ? 'No weekly prices published for ${row.ticker}.'
                            : '${plotted.length} weekly closes, the full '
                                  'published history · click a row above to '
                                  'chart it.',
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
          ],
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      row.shortName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: colors.textName,
                      ),
                    ),
                  ),
                  if (CategoryChip.maybe(row.category, dense: true)
                      case final chip?) ...[
                    const SizedBox(width: 6),
                    chip,
                  ],
                ],
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
