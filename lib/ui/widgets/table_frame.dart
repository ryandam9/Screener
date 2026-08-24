import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A bordered table: a header band, the rows, and a footer strip.
///
/// Desktop tables read as data when they are framed — a database client, a
/// spreadsheet — rather than as a list of cards floating on the page. The
/// handset keeps its unframed lists, where a border on every edge of a
/// full-width list is just noise.
class TableFrame extends StatelessWidget {
  const TableFrame({
    super.key,
    required this.header,
    required this.child,
    this.title,
    this.trailing,
    this.footer,
    this.margin = const EdgeInsets.all(20),
  });

  /// The column headings, shown on a tinted band.
  final Widget header;

  /// The rows. Expected to scroll.
  final Widget child;

  /// Optional caption above the headings, e.g. the table's name.
  final Widget? title;

  /// Optional control beside [title].
  final Widget? trailing;

  /// Optional strip under the rows, e.g. a row count.
  final Widget? footer;

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: margin,
      child: Material(
        color: colors.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.cardBorder)),
                ),
                child: Row(
                  children: [
                    Expanded(child: title!),
                    if (trailing != null) trailing!,
                  ],
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: colors.pageBackground,
                border: Border(bottom: BorderSide(color: colors.cardBorder)),
              ),
              child: header,
            ),
            Expanded(child: child),
            if (footer != null)
              Container(
                decoration: BoxDecoration(
                  color: colors.pageBackground,
                  border: Border(top: BorderSide(color: colors.cardBorder)),
                ),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}

/// A bordered page: the desktop frame around a one-column screen.
///
/// Settings, Analysis and Reports were laid out for a handset — cards floating
/// on a page background. Dropped into a desktop window they read as content
/// with no edges, since the window itself supplies none. Framing them gives
/// the pane a boundary, the same one the tables use, and keeps the section's
/// own app bar as its header band.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: margin,
      child: Material(
        // The page background, not the card colour: the panels inside are
        // cards, and they need something to sit on.
        color: colors.pageBackground,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.cardBorder),
        ),
        child: child,
      ),
    );
  }
}
