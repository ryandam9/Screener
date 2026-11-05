import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Shared workspace surface, including cards on the mobile dashboard.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.fill,
    this.border,
    this.borderWidth,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final Color? fill;
  final Color? border;
  final double? borderWidth;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Material(
      color: fill ?? context.colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        side: BorderSide(
          color: border ?? context.colors.cardBorder,
          width: borderWidth ?? AppBorders.border,
        ),
      ),
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// A card with native focus, keyboard activation and ink feedback.
class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.child,
    this.onTap,
    this.fill,
    this.border,
    this.borderWidth,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? fill;
  final Color? border;
  final double? borderWidth;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    fill: fill,
    border: border,
    borderWidth: borderWidth,
    margin: margin,
    child: Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class SurfaceTag extends StatelessWidget {
  const SurfaceTag({
    super.key,
    required this.label,
    this.fill,
    this.foreground,
    this.fontSize = 10,
    this.dense = false,
    this.leadingIcon,
  });

  final String label;

  /// Drawn before the label at the text's size, for a mark the app font
  /// does not carry (Roboto Condensed has no ▲ or ▼).
  final IconData? leadingIcon;
  final Color? fill;
  final Color? foreground;
  final double fontSize;
  final bool dense;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: dense ? 5 : 8,
      vertical: dense ? 2 : 4,
    ),
    decoration: BoxDecoration(
      color: fill ?? context.colors.neutralSurface,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingIcon != null)
          Icon(
            leadingIcon,
            // Scaled with the text beside it, so the pair keeps proportion
            // at any text size.
            size: MediaQuery.textScalerOf(context).scale(fontSize * 1.4),
            color: foreground ?? context.colors.textSecondary,
          ),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: foreground ?? context.colors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class DeltaBadge extends StatelessWidget {
  const DeltaBadge({
    super.key,
    required this.pctChange,
    this.fontSize = 13,
    this.dense = false,
  });

  final double pctChange;
  final double fontSize;
  final bool dense;

  @override
  Widget build(BuildContext context) => Semantics(
    // The arrow is an icon, so it is said in words.
    label:
        '${pctChange >= 0 ? 'up' : 'down'} '
        '${pctChange.abs().toStringAsFixed(1)}%',
    excludeSemantics: true,
    child: SurfaceTag(
      leadingIcon: pctChange >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
      label: '${pctChange.abs().toStringAsFixed(1)}%',
      fill: context.colors.surfaceForChange(pctChange),
      foreground: context.colors.forChange(pctChange),
      fontSize: fontSize,
      dense: dense,
    ),
  );
}
