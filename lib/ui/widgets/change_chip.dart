import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// The pill showing a percentage move, e.g. `+545.1%`.
class ChangeChip extends StatelessWidget {
  const ChangeChip({
    super.key,
    required this.pctChange,
    this.decimals = 1,
    this.dense = false,
  });

  final double pctChange;
  final int decimals;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceForChange(pctChange),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        Fmt.signedPercent(pctChange, decimals: decimals),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: TextStyle(
          fontSize: dense ? 11 : 12.5,
          fontWeight: FontWeight.w600,
          color: colors.forChange(pctChange),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A small labelled badge, used for qualitative tags such as "High".
class TagBadge extends StatelessWidget {
  const TagBadge({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
