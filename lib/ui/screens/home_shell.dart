import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/growth_window.dart';
import '../../state/app_state.dart';
import '../../state/digest_router.dart';
import '../../theme/app_theme.dart';
import 'analysis_screen.dart';
import 'dashboard_screen.dart';
import 'market_list_screen.dart';
import 'more_screen.dart';
import 'watchlist_screen.dart';

/// Root scaffold with the five-tab bottom navigation from the design.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// True between raising the post-frame handler and it running.
  bool _handlingDigestRequest = false;

  void _goToMarkets() => setState(() => _index = 1);

  /// Lands on the 7-day list when the morning digest was tapped.
  ///
  /// Everything happens after the frame, never inside it. Both shells are
  /// built from `AppShell`'s LayoutBuilder — that is, during layout — and
  /// `selectWindow` notifies its listeners, which marks a provider above this
  /// widget dirty. Doing that mid-build throws, and it only throws when the
  /// window actually changes: the crash hid until someone tapped a digest
  /// while looking at a window other than 7D.
  void _consumeDigestRequest(BuildContext context) {
    if (_handlingDigestRequest) return;
    if (!context.read<DigestRouter>().showSevenDayList) return;
    _handlingDigestRequest = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlingDigestRequest = false;
      if (!mounted) return;
      final router = context.read<DigestRouter>();
      if (!router.showSevenDayList) return;
      router.consume();
      context.read<AppState>().selectWindow(GrowthWindow.sevenDays);
      setState(() => _index = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appState = context.watch<AppState>();
    context.watch<DigestRouter>();
    _consumeDigestRequest(context);

    final pages = [
      DashboardScreen(onSeeAllMarkets: _goToMarkets),
      MarketListScreen(market: appState.selectedMarket),
      const WatchlistScreen(),
      const AnalysisScreen(),
      const MoreScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.cardBorder)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Markets',
            ),
            NavigationDestination(
              icon: Icon(Icons.star_border_rounded),
              selectedIcon: Icon(Icons.star_rounded),
              label: 'Watchlist',
            ),
            NavigationDestination(
              icon: Icon(Icons.speed_outlined),
              selectedIcon: Icon(Icons.speed),
              label: 'Analysis',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              selectedIcon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
