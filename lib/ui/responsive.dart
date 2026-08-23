import 'package:flutter/widgets.dart';

/// Layout sizes the app switches between.
///
/// The handset layout (bottom navigation, one column) and the desktop layout
/// (sidebar, multi-column dashboard) are two arrangements of the same screens
/// and the same data layer, chosen from the available width rather than from
/// the host platform — so a narrow desktop window gets the phone layout, which
/// is exactly what resizing the Linux window does.
enum LayoutSize {
  handset,
  desktop;

  static const double desktopBreakpoint = 900;

  static LayoutSize forWidth(double width) =>
      width >= desktopBreakpoint ? LayoutSize.desktop : LayoutSize.handset;

  bool get isDesktop => this == LayoutSize.desktop;
}

extension LayoutSizeX on BuildContext {
  /// The layout the current window width calls for.
  LayoutSize get layoutSize =>
      LayoutSize.forWidth(MediaQuery.sizeOf(this).width);
}
