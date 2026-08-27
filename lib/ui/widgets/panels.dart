import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A titled section with an optional trailing action, e.g. "View all".
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.caption,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 8, 8),
  });

  final String title;

  /// A word for what the column under this heading holds, e.g. "median
  /// volume". Sits over the values once, rather than being repeated on every
  /// row of the panel below.
  final String? caption;

  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
            ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: colors.positive,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// White rounded container used for every grouped block.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // A Material rather than a decorated box: the rows inside are tappable, and
    // ink splashes are painted by the nearest Material ancestor. A plain
    // coloured container here would sit on top of those splashes and hide them.
    return Padding(
      padding: margin,
      child: Material(
        color: colors.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.cardBorder),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A label/value line, as used by the Detailed Metrics list.
class MetricRow extends StatelessWidget {
  const MetricRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.monospaceValue = true,
    this.dense = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool monospaceValue;

  /// Tighter type and padding, for rows shown two-up in a narrow column.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 11 : 14,
        vertical: dense ? 10 : 11,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The label takes its natural width, capped at half the row: two
            // flex children would split the row evenly and leave the value's
            // right alignment stranded in the middle. It gives way first — it is
            // short and known, and shortening it never hides data.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.5),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: dense ? 12 : 13.5,
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Expanded rather than Flexible, so the value's right alignment
            // reaches the edge of the row instead of sitting against the label.
            // Values are never truncated — a run id wraps onto a second line
            // rather than ending in an ellipsis that cannot be read or copied.
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: dense ? 12.5 : 13.5,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? colors.textPrimary,
                  fontFeatures: monospaceValue
                      ? const [FontFeature.tabularFigures()]
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A bordered tile holding one headline metric.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.caption,
    this.captionColor,
    this.badge,
    this.trailing,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final String? caption;
  final Color? captionColor;
  final Widget? badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: valueColor ?? colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: captionColor ?? colors.textSecondary,
              ),
            ),
          ],
          if (badge != null) ...[const SizedBox(height: 7), badge!],
        ],
      ),
    );
  }
}

/// Empty / error / loading placeholder shared by the lists.
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Centred while it fits, scrollable when it does not: with large text, or
    // inside a short panel, the icon and message are taller than the space.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 32,
                vertical: compact ? 24 : 48,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: compact ? 30 : 38,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                  if (actionLabel != null) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented period selector (`7D 1M 3M 6M 1Y`).
class PeriodSelector<T> extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.compact = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  /// Sized to its labels rather than spread across the row, for a selector
  /// that sits in a panel header beside a title.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Every option is drawn as a button, not only the selected one: an
    // unselected period used to be bare text on the card, which gave no clue
    // that it could be clicked at all.
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values) ...[
            if (value != values.first) const SizedBox(width: 6),
            _PeriodPill(
              label: labelOf(value),
              selected: value == selected,
              onTap: () => onChanged(value),
              dense: true,
            ),
          ],
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final value in values)
          Expanded(
            child: Center(
              child: _PeriodPill(
                label: labelOf(value),
                selected: value == selected,
                onTap: () => onChanged(value),
              ),
            ),
          ),
      ],
    );
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? colors.positive : colors.pageBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? colors.positive : colors.cardBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          // A pointer cursor, because on a desktop that is half the signal.
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 11 : 16,
              vertical: dense ? 5 : 7,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: dense ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
