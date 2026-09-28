import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The poster language: a hard ink border, no radius, and a solid shadow
/// offset down and right.
///
/// The shadow is not a blur. It is a second, flat rectangle of ink sitting
/// behind the box — the thing that makes a sticker look like a sticker. Every
/// surface in the app that used to be a soft rounded card is one of these, so
/// the border width and the offset are tokens rather than literals: change
/// them here and the whole app changes weight together.
class BrutalBox extends StatelessWidget {
  const BrutalBox({
    super.key,
    required this.child,
    this.fill,
    this.border,
    this.borderWidth,
    this.shadow = true,
    this.offset,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;

  /// Defaults to the card colour.
  final Color? fill;

  /// Defaults to [ScreenerColors.ink].
  final Color? border;
  final double? borderWidth;

  /// Whether to cast the solid offset shadow. Off for boxes nested inside
  /// another box, where a second shadow reads as a mistake rather than depth.
  final bool shadow;

  /// How far the shadow sits down and right. Defaults to [AppBrut.offset].
  final double? offset;

  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = border ?? colors.ink;
    final width = borderWidth ?? AppBrut.border;
    final drop = offset ?? AppBrut.offset;

    // A Material rather than a DecoratedBox: the rows inside are tappable, and
    // ink is painted by the nearest Material ancestor. A plain coloured box
    // here would sit on top of those splashes and swallow them — and the
    // starred-row wash would be invisible to anything reading the surface.
    final box = Material(
      color: fill ?? colors.card,
      type: MaterialType.canvas,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: ink, width: width),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (!shadow) return Padding(padding: margin, child: box);

    // The box gives up [drop] on its right and bottom and the shadow takes
    // exactly that strip, so the whole thing still occupies one rectangle and
    // a shadow can never paint over the row beneath it. Drawing the shadow as
    // a sibling rather than as a BoxShadow keeps it perfectly hard-edged at
    // every device pixel ratio — a zero-blur BoxShadow still antialiases.
    return Padding(
      padding: margin,
      child: Stack(
        children: [
          Positioned(
            left: drop,
            top: drop,
            right: 0,
            bottom: 0,
            child: ColoredBox(color: ink),
          ),
          Padding(
            padding: EdgeInsets.only(right: drop, bottom: drop),
            child: box,
          ),
        ],
      ),
    );
  }
}

/// A [BrutalBox] that presses into its own shadow.
///
/// Tapping moves the box down and right by exactly the shadow's offset while
/// the shadow shrinks to nothing, so the card looks pushed flat against the
/// page and springs back on release. It is the one piece of motion in the app
/// that exists for pleasure rather than orientation, which is why it is short
/// and why reduced-motion turns it into a plain state change.
class BrutalPressable extends StatefulWidget {
  const BrutalPressable({
    super.key,
    required this.child,
    this.onTap,
    this.fill,
    this.border,
    this.borderWidth,
    this.offset,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? fill;
  final Color? border;
  final double? borderWidth;
  final double? offset;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final String? semanticLabel;

  @override
  State<BrutalPressable> createState() => _BrutalPressableState();
}

class _BrutalPressableState extends State<BrutalPressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final drop = widget.offset ?? AppBrut.offset;
    final enabled = widget.onTap != null;
    final pressed = _down && enabled;
    final duration = AppMotion.selectionDuration(context);

    return Padding(
      padding: widget.margin,
      child: Semantics(
        button: enabled,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _set(true),
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
            child: Stack(
              children: [
                // The shadow is always there. Pressing slides the box down and
                // right onto it until it covers it exactly, which is why this
                // needs no second state: the card looks pushed flat against
                // the page and springs back on release.
                Positioned(
                  left: drop,
                  top: drop,
                  right: 0,
                  bottom: 0,
                  child: ColoredBox(color: widget.border ?? colors.ink),
                ),
                AnimatedPadding(
                  duration: duration,
                  curve: Curves.easeOut,
                  // Padding rather than a Transform, so the footprint never
                  // changes and a pressed row cannot overlap the one below it.
                  padding: pressed
                      ? EdgeInsets.only(left: drop, top: drop)
                      : EdgeInsets.only(right: drop, bottom: drop),
                  child: BrutalBox(
                    fill: widget.fill,
                    border: widget.border,
                    borderWidth: widget.borderWidth,
                    shadow: false,
                    padding: widget.padding,
                    child: widget.child,
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

/// A hard-edged label block: the app's answer to a rounded chip.
///
/// Set in caps with wide tracking, because at these sizes the shape of the
/// block does the work a rounded pill's silhouette used to do.
class BrutalTag extends StatelessWidget {
  const BrutalTag({
    super.key,
    required this.label,
    this.fill,
    this.foreground,
    this.fontSize = 10,
    this.dense = false,
  });

  final String label;
  final Color? fill;
  final Color? foreground;
  final double fontSize;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : 7,
        vertical: dense ? 1 : 2.5,
      ),
      decoration: BoxDecoration(
        color: fill ?? colors.neutralSurface,
        border: Border.all(color: colors.ink, width: AppBrut.hairline),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: foreground ?? colors.ink,
        ),
      ),
    );
  }
}

/// A percentage rendered as a filled block rather than coloured text.
///
/// The old design said "up" with green text on white, which is the one thing
/// the contrast guidance keeps flagging: a 3:1 hue carrying the most important
/// number on the row. Here the hue is the *background*, the text on it is ink,
/// and the sign is spelled out — so it reads at a glance, passes contrast, and
/// still works for someone who cannot separate the two hues.
class DeltaBlock extends StatelessWidget {
  const DeltaBlock({
    super.key,
    required this.pctChange,
    this.fontSize = 13,
    this.dense = false,
  });

  final double pctChange;
  final double fontSize;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final up = pctChange >= 0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: up ? colors.positiveSurface : colors.negativeSurface,
        border: Border.all(color: colors.ink, width: AppBrut.hairline),
      ),
      child: Text(
        '${up ? '▲' : '▼'} ${pctChange.abs().toStringAsFixed(1)}%',
        maxLines: 1,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: colors.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A section heading in the poster voice: caps, heavy, with a rule under it.
class BrutalHeading extends StatelessWidget {
  const BrutalHeading({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 26, 16, 10),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final action = actionLabel;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  // Set in caps, read out in sentence case: some screen
                  // readers spell an all-caps word letter by letter.
                  semanticsLabel: title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (action != null && onAction != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onAction,
                  child: BrutalTag(
                    label: action,
                    fill: colors.interactive,
                    foreground: colors.onInteractive,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(height: AppBrut.border, color: colors.ink),
        ],
      ),
    );
  }
}
