import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// A titled block on the desktop dashboard, with an optional trailing action.
class DesktopPanel extends StatelessWidget {
  const DesktopPanel({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
    this.leadingAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Extra control shown before [actionLabel], e.g. an external link.
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.panel),
        side: BorderSide(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              15,
              actionLabel == null && leadingAction == null ? 18 : 8,
              12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (leadingAction != null) leadingAction!,
                if (actionLabel != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.interactive,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(actionLabel!),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Small rounded ticker label used in the desktop tables.
class TickerChip extends StatelessWidget {
  const TickerChip({super.key, required this.ticker});

  final String ticker;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.neutralSurface,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        ticker,
        // A ticker on two lines is not a ticker. NSE symbols run to ten
        // characters, which is what the column is sized for; anything longer
        // than that gives up a character rather than the row's height.
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
