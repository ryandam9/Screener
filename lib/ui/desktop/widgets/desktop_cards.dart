import 'package:flutter/material.dart';

import '../../../data/market_database.dart';
import '../../../models/growth_window.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';
import '../../widgets/sparkline.dart';

/// A titled block on the desktop dashboard, with an optional trailing action.
class DesktopPanel extends StatelessWidget {
  const DesktopPanel({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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
              actionLabel == null ? 18 : 8,
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
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (actionLabel != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.positive,
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

/// Shared frame for the four cards along the top of the dashboard.
class _StatCardFrame extends StatelessWidget {
  const _StatCardFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// ASX / US card: median change for the window, over a sparkline of the median
/// across every window the file publishes.
class MarketSummaryCard extends StatelessWidget {
  const MarketSummaryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.window,
    required this.instrumentNoun,
  });

  final String title;
  final String subtitle;
  final MarketSummary? summary;
  final GrowthWindow window;
  final String instrumentNoun;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final stat = summary?.statFor(window);
    final trend = [
      for (final entry in summary?.stats ?? const <WindowStat>[])
        if (entry.count > 0) entry.medianPctChange,
    ];

    return _StatCardFrame(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: trend.length >= 2
                ? Sparkline(values: trend, color: colors.positive)
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          if (stat == null || stat.count == 0)
            Text(
              summary == null ? 'Loading…' : 'No rows',
              style: TextStyle(fontSize: 16, color: colors.textTertiary),
            )
          else ...[
            Text(
              Fmt.signedPercent(stat.medianPctChange, decimals: 2),
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.7,
                color: colors.forChange(stat.medianPctChange),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'median ${window.label} · ${Fmt.integer(stat.count)} $instrumentNoun',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Median change across the starred tickers that appear in the window.
class WatchlistPerformanceCard extends StatelessWidget {
  const WatchlistPerformanceCard({
    super.key,
    required this.median,
    required this.count,
    required this.window,
  });

  final double? median;
  final int count;
  final GrowthWindow window;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final median = this.median;

    return _StatCardFrame(
      title: 'Watchlist Performance',
      subtitle: 'My Watchlist',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: median == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.star_border_rounded,
                      color: colors.textTertiary,
                      size: 26,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          if (median == null) ...[
            Text(
              'Nothing starred',
              style: TextStyle(fontSize: 16, color: colors.textTertiary),
            ),
            const SizedBox(height: 3),
            Text(
              'Star a ticker to track it here',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
          ] else ...[
            Text(
              Fmt.signedPercent(median, decimals: 2),
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.7,
                color: colors.forChange(median),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'median ${window.label} · ${Fmt.integer(count)} '
              '${count == 1 ? 'item' : 'items'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Run-level totals.
///
/// The mockup pairs each number with a month-on-month delta. The databases
/// carry a single run id, so there is no earlier run to compare against and no
/// honest delta to show; the card says so instead of inventing one.
class AnalysisSummaryCard extends StatelessWidget {
  const AnalysisSummaryCard({
    super.key,
    required this.analyses,
    required this.rows,
    required this.averageReturn,
    required this.window,
  });

  final int analyses;

  /// Total published rows, counting a ticker once per window it appears in.
  final int rows;
  final double? averageReturn;
  final GrowthWindow window;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // The average needs more room than the two counts: it carries a sign, a
    // decimal and a percent sign, and ellipsized to "+19.0…" at equal widths.
    Widget stat(String label, String value, {Color? valueColor, int flex = 1}) {
      return Expanded(
        flex: flex,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: valueColor ?? colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return _StatCardFrame(
      title: 'Analysis Summary',
      subtitle: 'Latest run',
      trailing: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: colors.positiveSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.insights, size: 18, color: colors.positive),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                stat('Analyses', Fmt.integer(analyses)),
                stat('Rows', Fmt.integer(rows)),
                stat(
                  'Avg ${window.label}',
                  averageReturn == null
                      ? '—'
                      : Fmt.signedPercent(averageReturn!, decimals: 1),
                  valueColor: averageReturn == null
                      ? null
                      : colors.forChange(averageReturn!),
                  flex: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'One published run',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'no earlier run to compare against',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Small rounded ticker label used in the desktop tables.
class TickerChip extends StatelessWidget {
  const TickerChip({super.key, required this.ticker});

  final String ticker;

  static const _palette = <(Color, Color)>[
    (Color(0xFF1F6F5C), Color(0xFFD9EFE8)),
    (Color(0xFF2C5AA0), Color(0xFFDDE7F7)),
    (Color(0xFF8A5A2B), Color(0xFFF6E7D5)),
    (Color(0xFF6A4C93), Color(0xFFEBE2F6)),
    (Color(0xFF9C2C4E), Color(0xFFF8DFE6)),
    (Color(0xFF2F6E8F), Color(0xFFDCECF4)),
  ];

  @override
  Widget build(BuildContext context) {
    var hash = 0;
    for (final unit in ticker.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final (foreground, background) = _palette[hash % _palette.length];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? foreground.withValues(alpha: 0.3) : background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        ticker,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: isDark ? background : foreground,
        ),
      ),
    );
  }
}
