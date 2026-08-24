import 'package:flutter/material.dart';

import '../../models/stock_row.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// Why a ticker is in the file at all: it cleared the window's screen.
///
/// Every published row passed a cut-off — 10% over a week, 25% over a year —
/// and the file records the one that was applied. Without it on screen the
/// lists look like an unexplained selection of tickers; with it, each row
/// carries the rule it satisfied.
class ScreenReason extends StatelessWidget {
  const ScreenReason({super.key, required this.row});

  final StockRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cutOff = row.threshold;

    // Files published before the column existed say nothing rather than
    // guessing a rule that may not have been the one applied.
    if (cutOff == null) return const SizedBox.shrink();

    final margin = row.marginOverThreshold ?? 0;
    // Percentage points, not percent: the gap between two percentages.
    final marginText = margin.abs().toStringAsFixed(1);
    final cleared = margin >= 0;
    final tint = cleared ? colors.positive : colors.warning;
    final surface = cleared ? colors.positiveSurface : colors.warningSurface;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 14, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            cleared ? Icons.filter_alt_outlined : Icons.warning_amber_rounded,
            size: 17,
            color: tint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cleared ? 'Why it is listed' : 'Below the cut-off',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  cleared
                      ? 'Its ${row.window.longLabel.toLowerCase()} change of '
                            '${Fmt.signedPercent(row.pctChange, decimals: 1)} '
                            'is past the ${Fmt.percent(cutOff, decimals: 1)} '
                            'cut-off this screen applies, by '
                            '$marginText points.'
                      : 'Its ${row.window.longLabel.toLowerCase()} change of '
                            '${Fmt.signedPercent(row.pctChange, decimals: 1)} '
                            'is under the ${Fmt.percent(cutOff, decimals: 1)} '
                            'cut-off this screen applies.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The cut-off on its own, for a caption beside a list's row count.
String? screenCutOffLabel(double? threshold) =>
    threshold == null ? null : 'cut-off ${Fmt.percent(threshold, decimals: 1)}';
