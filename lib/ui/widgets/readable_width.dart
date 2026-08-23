import 'package:flutter/material.dart';

/// Caps and centres content that was laid out for a handset.
///
/// The lists and the detail screen are one-column designs. Stretched across a
/// full desktop window they leave a company name and its price at opposite
/// edges, with a void between. Constraining them keeps the columns readable;
/// the dashboard, which is designed for the width, is not wrapped.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({
    super.key,
    required this.child,
    this.maxWidth = kReadableWidth,
  });

  static const double kReadableWidth = 980;

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
