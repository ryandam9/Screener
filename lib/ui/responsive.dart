import 'package:flutter/widgets.dart';

/// Layout sizes the app switches between.
///
/// Three rather than two. The screens and the data layer are the same at every
/// width; what changes is where the navigation lives and whether a list and
/// the thing it opens can sit side by side. Chosen from the available width
/// rather than from the host platform, so resizing the Linux window walks
/// through all three.
enum LayoutSize {
  /// Bottom navigation, one column, a tapped row opens a page.
  handset,

  /// A navigation rail, still one column: there is room for the rail but not
  /// for a list and a detail pane that are both worth reading. A 950px window
  /// split into a 380px list and a 560px pane gave neither enough.
  compact,

  /// Sidebar, and two panes side by side.
  desktop;

  static const double compactBreakpoint = 720;
  static const double desktopBreakpoint = 1100;

  static LayoutSize forWidth(double width) => switch (width) {
    >= desktopBreakpoint => LayoutSize.desktop,
    >= compactBreakpoint => LayoutSize.compact,
    _ => LayoutSize.handset,
  };

  bool get isHandset => this == LayoutSize.handset;
  bool get isCompact => this == LayoutSize.compact;
  bool get isDesktop => this == LayoutSize.desktop;

  /// Navigation is a rail or a sidebar down the side, not a bar along the
  /// bottom. True for everything but a handset.
  bool get hasSidebar => this != LayoutSize.handset;

  /// A list and the row it opens can share the window. Only the widest tier:
  /// below it the detail takes the pane and a back action returns to the list.
  bool get hasSplitPanes => this == LayoutSize.desktop;
}

extension LayoutSizeX on BuildContext {
  /// The layout the current window width calls for.
  LayoutSize get layoutSize =>
      LayoutSize.forWidth(MediaQuery.sizeOf(this).width);
}
