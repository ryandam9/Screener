import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../models/stock_row.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'change_chip.dart';
import 'google_finance_button.dart';
import 'ticker_avatar.dart';
import 'watchlist_star.dart';

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
  ///
  /// Sized to the values they hold ("139.22", "+117.9%") rather than to round
  /// numbers, and scaled with the reader's text size — a column fixed in
  /// pixels ellipsizes its own numbers at 1.3x.
  static double priceColumn(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(52);

  static double changeColumn(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(72);

  static const double leadingColumnWidth = 38 + 12;

  /// The star and the external link at the end of every row.
  static const double actionsWidth = 26 * 2;

  /// Below this much space for the ticker and company name, the row drops
  /// what it can rather than overflowing: first the market badge, then the
  /// price column. A 320dp phone at 1.3x text hits both.
  static const double _minNameWidth = 96;

  /// How much room the ticker and name have once everything else is placed.
  static double nameSpace(
    BuildContext context,
    double width, {
    bool dense = false,
    bool withPrice = true,
  }) {
    final leading = 16 + (dense ? 32 : 38) + 12;
    final trailing =
        6 +
        (withPrice ? priceColumn(context) + 6 : 0) +
        changeColumn(context) +
        actionsWidth +
        16;
    return width - leading - trailing;
  }

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
    return LayoutBuilder(
      builder: (context, constraints) => _row(context, constraints),
    );
  }

  Widget _row(BuildContext context, BoxConstraints constraints) {
    final colors = context.colors;
    final width = constraints.maxWidth;
    final showPrice =
        trailingBuilder != null ||
        StockTile.nameSpace(context, width, dense: dense) >=
            StockTile._minNameWidth;
    final space = StockTile.nameSpace(
      context,
      width,
      dense: dense,
      withPrice: showPrice,
    );
    final showBadge = showMarketBadge && space >= StockTile._minNameWidth + 28;

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
                    if (showBadge) ...[
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
          const SizedBox(width: 6),
          // A caller-supplied trailing widget is sized by its own content, so
          // it flexes: at 320dp with large text it would otherwise push the
          // row past its edge.
          if (trailingBuilder != null)
            Flexible(child: trailingBuilder!(context))
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showPrice) ...[
                  SizedBox(
                    width: StockTile.priceColumn(context),
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
                  const SizedBox(width: 6),
                ],
                SizedBox(
                  width: StockTile.changeColumn(context),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ChangeChip(pctChange: row.pctChange, dense: dense),
                  ),
                ),
              ],
            ),
          // Star and quote page, both from the row itself.
          WatchlistStar(market: row.market, ticker: row.ticker, dense: true),
          if (row.googleFinanceUrl != null)
            GoogleFinanceButton(
              url: row.googleFinanceUrl,
              ticker: row.ticker,
              dense: true,
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
    return LayoutBuilder(
      builder: (context, constraints) => _row(context, colors, constraints),
    );
  }

  Widget _row(
    BuildContext context,
    ScreenerColors colors,
    BoxConstraints constraints,
  ) {
    // "+75.33 (+117.9%)" needs 188px, and the row also carries a star, a link
    // and the ticker's market badge. Under about 400px that leaves the company
    // name nothing, so the percentage alone carries the row — it is what the
    // list is ranked on, and the absolute change is one tap away.
    final scaler = MediaQuery.textScalerOf(context);
    final tight = constraints.maxWidth < scaler.scale(400);
    // At 320dp with large text even the badge has to go.
    final space =
        constraints.maxWidth -
        (16 + 38 + 12 + 8 + scaler.scale(tight ? 72 : 188) + 52 + 16);
    final showBadge = showMarketBadge && space >= 124;

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
                    if (showBadge) ...[
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
          const SizedBox(width: 8),
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
                tight
                    ? Fmt.signedPercent(row.pctChange, decimals: 1)
                    : '${Fmt.signedPrice(row.priceChange)} '
                          '(${Fmt.signedPercent(row.pctChange, decimals: 1)})',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colors.forChange(row.pctChange),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          WatchlistStar(market: row.market, ticker: row.ticker, dense: true),
          if (row.googleFinanceUrl != null)
            GoogleFinanceButton(
              url: row.googleFinanceUrl,
              ticker: row.ticker,
              dense: true,
            ),
        ],
      ),
    );
  }
}
