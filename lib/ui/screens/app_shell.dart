import 'package:flutter/material.dart';

import '../desktop/desktop_shell.dart';
import '../responsive.dart';
import 'home_shell.dart';

/// The sections reachable from the navigation, in sidebar order.
///
/// The handset layout shows the first three plus Settings in its bottom bar;
/// the desktop sidebar shows all of them.
enum AppSection {
  dashboard('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
  markets('Markets', Icons.public_outlined, Icons.public),
  watchlist('Watchlist', Icons.star_border_rounded, Icons.star_rounded),
  // Deliberately not a variation on the brand mark, which is already
  // `trending_up`: History is a price series, so it gets candlesticks.
  history('History', Icons.candlestick_chart_outlined, Icons.candlestick_chart),
  reports('Reports', Icons.description_outlined, Icons.description),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const AppSection(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Picks the layout from the window width.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return LayoutSize.forWidth(constraints.maxWidth).hasSidebar
            ? const DesktopShell()
            : const HomeShell();
      },
    );
  }
}
