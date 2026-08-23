import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/market.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../screens/analysis_screen.dart';
import '../screens/app_shell.dart';
import '../screens/market_list_screen.dart';
import '../screens/more_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/watchlist_screen.dart';
import '../widgets/readable_width.dart';
import 'desktop_dashboard.dart';

/// The wide layout: a persistent sidebar beside the active section.
///
/// Each section reuses the screen the handset layout uses, so there is one
/// implementation of every list and query; only the navigation chrome and the
/// dashboard differ between the two sizes.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  AppSection _section = AppSection.dashboard;

  /// Set when the dashboard's search box submits, so the Markets section opens
  /// already filtered.
  String? _pendingSearch;

  void _openMarkets(String? search) {
    setState(() {
      _pendingSearch = search;
      _section = AppSection.markets;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appState = context.watch<AppState>();

    // The dashboard is built for the width; the rest are handset layouts and
    // are capped so their columns stay together.
    final Widget content = switch (_section) {
      AppSection.dashboard => DesktopDashboard(
        onSearchSubmitted: _openMarkets,
        onViewAllGainers: () => _openMarkets(null),
      ),
      AppSection.markets => MarketListScreen(
        key: ValueKey('markets-${_pendingSearch ?? ''}'),
        market: appState.selectedMarket,
        initialSearch: _pendingSearch,
      ),
      AppSection.watchlist => const WatchlistScreen(),
      AppSection.analysis => const AnalysisScreen(),
      AppSection.reports => const ReportsScreen(),
      AppSection.settings => const MoreScreen(),
    };

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            section: _section,
            onSelect: (section) => setState(() {
              _section = section;
              if (section != AppSection.markets) _pendingSearch = null;
            }),
          ),
          Container(width: 1, color: colors.cardBorder),
          Expanded(
            // Sections fade through one another rather than cutting, so the
            // sidebar selection and the content stay visibly connected.
            child: PageTransitionSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, animation, secondaryAnimation) =>
                  FadeThroughTransition(
                    animation: animation,
                    secondaryAnimation: secondaryAnimation,
                    fillColor: Colors.transparent,
                    child: child,
                  ),
              child: KeyedSubtree(
                key: ValueKey('${_section.name}-${_pendingSearch ?? ''}'),
                child: _section == AppSection.dashboard
                    ? content
                    : ReadableWidth(child: content),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.section, required this.onSelect});

  final AppSection section;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 236,
      color: colors.card,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.positiveSurface,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.trending_up,
                      size: 19,
                      color: colors.positive,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Stocks Analysis',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final value in AppSection.values)
              _NavItem(
                section: value,
                selected: value == section,
                onTap: () => onSelect(value),
              ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 14, 14, 18),
              child: _DataStatusCard(),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final AppSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? colors.positiveSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected ? section.selectedIcon : section.icon,
                  size: 20,
                  color: selected ? colors.positive : colors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? colors.positive : colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card at the foot of the sidebar.
///
/// The mockup shows a market-open countdown here. Nothing in the published
/// databases describes trading sessions, so this reports what the app does
/// know — whether both files are current and how fresh the screener run is —
/// above a live local clock.
class _DataStatusCard extends StatefulWidget {
  const _DataStatusCard();

  @override
  State<_DataStatusCard> createState() => _DataStatusCardState();
}

class _DataStatusCardState extends State<_DataStatusCard> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appState = context.watch<AppState>();

    final busy = appState.anyBusy;
    final cached = Market.values.any((m) => appState.stateOf(m).usingCache);
    final ready = appState.allReady;

    final (Color tint, String label) = busy
        ? (colors.neutral, 'Syncing…')
        : cached
        ? (colors.warning, 'Cached data')
        : ready
        ? (colors.positive, 'Databases current')
        : (colors.negative, 'Data unavailable');

    String? asOf;
    for (final market in Market.values) {
      final summary = appState.stateOf(market).asset;
      if (summary != null) {
        asOf = Fmt.relativeStamp(summary.syncedAt, now: _now);
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: colors.pageBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (asOf != null) ...[
            const SizedBox(height: 3),
            Text(
              'Synced $asOf',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            Fmt.date(_now.toIso8601String().substring(0, 10)),
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          Text(
            Fmt.clock(_now),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
