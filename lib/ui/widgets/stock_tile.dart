import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../models/stock_row.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'change_chip.dart';
import 'ticker_avatar.dart';

/// A row in the market list: monogram, ticker + name, price, change chip.
class StockTile extends StatelessWidget {
  const StockTile({
    super.key,
    required this.row,
    this.onTap,
    this.opensTo,
    this.dense = false,
    this.showMarketBadge = false,
    this.trailingBuilder,
  });

  final StockRow row;
  final VoidCallback? onTap;

  /// Screen this row opens. Given one, the row grows into it — a container
  /// transform — rather than having the destination slide over it. [onTap] is
  /// the fallback for rows that navigate some other way, or not at all.
  final WidgetBuilder? opensTo;
  final bool dense;
  final bool showMarketBadge;
  final Widget Function(BuildContext context)? trailingBuilder;

  /// Column geometry shared with the sortable header above the list, so the
  /// headings sit directly over the values they sort.
  static const double priceColumnWidth = 58;
  static const double changeColumnWidth = 80;
  static const double leadingColumnWidth = 38 + 12;

  @override
  Widget build(BuildContext context) {
    final open = opensTo;
    if (open != null) {
      final colors = context.colors;
      return OpenContainer<void>(
        tappable: true,
        closedElevation: 0,
        openElevation: 0,
        closedColor: colors.card,
        openColor: colors.pageBackground,
        middleColor: colors.card,
        transitionDuration: const Duration(milliseconds: 380),
        closedShape: const RoundedRectangleBorder(),
        closedBuilder: (context, _) => _content(context),
        openBuilder: (context, _) => open(context),
      );
    }
    return InkWell(onTap: onTap, child: _content(context));
  }

  Widget _content(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 8 : 11),
      child: Row(
        children: [
          TickerAvatar(ticker: row.ticker, size: dense ? 32 : 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.ticker,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: dense ? 13.5 : 14.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (showMarketBadge) ...[
                      const SizedBox(width: 6),
                      TagBadge(
                        label: row.market.label,
                        foreground: colors.neutral,
                        background: colors.neutralSurface,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  row.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 11.5 : 12.5,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailingBuilder?.call(context) ??
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: StockTile.priceColumnWidth,
                    child: Text(
                      Fmt.price(row.latestPrice),
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 13.5 : 14.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: StockTile.changeColumnWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ChangeChip(pctChange: row.pctChange, dense: dense),
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

/// Dashboard variant: name on the left, price above the signed change.
class GainerTile extends StatelessWidget {
  const GainerTile({
    super.key,
    required this.row,
    this.onTap,
    this.opensTo,
    this.showMarketBadge = true,
  });

  final StockRow row;
  final VoidCallback? onTap;

  /// Screen this row grows into. See [StockTile.opensTo].
  final WidgetBuilder? opensTo;

  final bool showMarketBadge;

  @override
  Widget build(BuildContext context) {
    final open = opensTo;
    if (open != null) {
      final colors = context.colors;
      return OpenContainer<void>(
        tappable: true,
        closedElevation: 0,
        openElevation: 0,
        closedColor: colors.card,
        openColor: colors.pageBackground,
        middleColor: colors.card,
        transitionDuration: const Duration(milliseconds: 380),
        closedShape: const RoundedRectangleBorder(),
        closedBuilder: (context, _) => _content(context),
        openBuilder: (context, _) => open(context),
      );
    }
    return InkWell(onTap: onTap, child: _content(context));
  }

  Widget _content(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          TickerAvatar(ticker: row.ticker, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.ticker,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (showMarketBadge) ...[
                      const SizedBox(width: 6),
                      TagBadge(
                        label: row.market.label,
                        foreground: colors.neutral,
                        background: colors.neutralSurface,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  row.shortName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Fmt.price(row.latestPrice),
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${Fmt.signedPrice(row.priceChange)} (${Fmt.signedPercent(row.pctChange, decimals: 1)})',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.forChange(row.pctChange),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
