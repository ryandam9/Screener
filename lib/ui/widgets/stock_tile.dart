import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../../models/stock_row.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'category_chip.dart';
import 'change_chip.dart';
import 'google_finance_button.dart';
import 'ticker_avatar.dart';
import 'watchlist_highlight.dart';
import 'watchlist_star.dart';

/// A row in the market list: monogram, ticker + name, price, change chip.
class StockTile extends StatelessWidget {
  const StockTile({
    super.key,
    required this.row,
    this.onTap,
    this.opensTo,
    this.selected = false,
    this.dense = false,
    this.showMarketBadge = false,
  });

  final StockRow row;
  final VoidCallback? onTap;

  /// Marks the row the detail pane is showing, in the desktop master-detail
  /// layout. A pushed screen has no need for it.
  final bool selected;

  /// Screen this row opens. Given one, the row grows into it — a container
  /// transform — rather than having the destination slide over it. [onTap] is
  /// the fallback for rows that navigate some other way, or not at all.
  final WidgetBuilder? opensTo;
  final bool dense;
  final bool showMarketBadge;

  /// Column geometry shared with the sortable header above the list, so the
  /// headings sit directly over the values they sort.
  ///
  /// Sized to the values they hold ("139.22", "+117.9%") rather than to round
  /// numbers, and scaled with the reader's text size — a column fixed in
  /// pixels ellipsizes its own numbers at 1.3x.
  static double priceColumn(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(58);

  static double changeColumn(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(72);

  /// The monogram and the gap after it, before the ticker starts.
  static double leadingColumn({bool dense = false}) => (dense ? 32 : 38) + 12;

  /// The gap between the name and the first number, and between the numbers.
  static const double columnGap = 6;

  /// One icon button: the star, or the link beside it.
  static const double actionWidth = 26;

  /// The star and the external link at the end of every row.
  static const double actionsWidth = actionWidth * 2;

  /// Below this much space for the ticker and company name, the row drops
  /// what it can rather than overflowing: first the market badge, then the
  /// price column. A 320dp phone at 1.3x text hits both.
  static const double _minNameWidth = 96;

  /// Below this, the name gets a line of its own under the ticker instead of
  /// sharing one with the numbers.
  ///
  /// A phone leaves the name column around 112px beside the price and the
  /// change chip, which is narrower than the word "Pharmaceuticals," — so the
  /// name was cut however many lines it was allowed. Across the full width it
  /// simply fits.
  static const double comfortableNameWidth = 168;

  /// How much room the ticker and name have once everything else is placed.
  static double nameSpace(
    BuildContext context,
    double width, {
    bool dense = false,
    bool withPrice = true,
  }) {
    final leading = 16 + leadingColumn(dense: dense);
    final trailing =
        columnGap +
        (withPrice ? priceColumn(context) + columnGap : 0) +
        changeColumn(context) +
        actionsWidth +
        16;
    return width - leading - trailing;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Starred rows are tinted wherever they are listed; see starredRowColor.
    final background = starredRowColor(
      context,
      row.market,
      row.ticker,
      selected: selected,
    );
    final open = opensTo;
    if (open != null) {
      return OpenContainer<void>(
        tappable: true,
        closedElevation: 0,
        openElevation: 0,
        // The tint has to be the container's own colour rather than something
        // painted inside it: OpenContainer fades the closed colour into the
        // opening screen, and a ColoredBox within would flash white here.
        closedColor: background ?? colors.card,
        openColor: colors.pageBackground,
        middleColor: colors.card,
        transitionDuration: const Duration(milliseconds: 380),
        closedShape: const RoundedRectangleBorder(),
        closedBuilder: (context, _) => _content(context),
        openBuilder: (context, _) => open(context),
      );
    }
    return Material(
      color: background ?? Colors.transparent,
      child: InkWell(onTap: onTap, child: _content(context)),
    );
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
        StockTile.nameSpace(context, width, dense: dense) >=
        StockTile._minNameWidth;
    final space = StockTile.nameSpace(
      context,
      width,
      dense: dense,
      withPrice: showPrice,
    );
    final showBadge = showMarketBadge && space >= StockTile._minNameWidth + 28;

    // Names matter more than compactness: below a comfortable width the name
    // moves to its own full-width line rather than being trimmed to fit.
    final nameBelow = space < StockTile.comfortableNameWidth;

    final name = _NameLine(
      name: row.shortName,
      // Three lines is generous for one line's worth of name in Inter, and
      // it is what keeps long names whole at large text sizes.
      maxLines: dense ? 2 : 3,
      fontSize: dense ? 11.5 : 12.5,
      color: colors.textName,
      // The chip travels with the name rather than with the ticker, so it
      // lands on whichever line the name did and never competes with the
      // market badge for the ticker's row.
      //
      // Smaller once the name has been pushed to its own line: there the chip
      // takes its width before the name gets any, and at 320dp a full-size
      // "Industrial Metals" leaves the name three cramped lines.
      chip: CategoryChip.maybe(row.category, dense: dense || nameBelow),
      // Under this there is not enough left for a name beside a chip, and the
      // name is the thing a reader needs.
      showChip: space >= StockTile.comfortableNameWidth || nameBelow,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 8 : 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                    if (!nameBelow) ...[const SizedBox(height: 1), name],
                  ],
                ),
              ),
              const SizedBox(width: 6),
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
              WatchlistStar(
                market: row.market,
                ticker: row.ticker,
                dense: true,
              ),
              // The link's slot is held even when a row has no URL: a row that
              // dropped it would pull its price and change 26px to the right of
              // every other row, and out from under the headings.
              if (row.googleFinanceUrl != null)
                GoogleFinanceButton(
                  url: row.googleFinanceUrl,
                  ticker: row.ticker,
                  dense: true,
                )
              else
                const SizedBox(width: StockTile.actionWidth),
            ],
          ),
          // The name on its own line, indented to sit under the ticker.
          if (nameBelow)
            Padding(
              padding: EdgeInsets.only(
                left: StockTile.leadingColumn(dense: dense),
                top: 2,
              ),
              child: name,
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
    this.selected = false,
    this.showMarketBadge = true,
  });

  final StockRow row;
  final VoidCallback? onTap;

  /// Screen this row grows into. See [StockTile.opensTo].
  final WidgetBuilder? opensTo;

  /// See [StockTile.selected].
  final bool selected;

  final bool showMarketBadge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // See StockTile.build.
    final background = starredRowColor(
      context,
      row.market,
      row.ticker,
      selected: selected,
    );
    final open = opensTo;
    if (open != null) {
      return OpenContainer<void>(
        tappable: true,
        closedElevation: 0,
        openElevation: 0,
        closedColor: background ?? colors.card,
        openColor: colors.pageBackground,
        middleColor: colors.card,
        transitionDuration: const Duration(milliseconds: 380),
        closedShape: const RoundedRectangleBorder(),
        closedBuilder: (context, _) => _content(context),
        openBuilder: (context, _) => open(context),
      );
    }
    return Material(
      color: background ?? Colors.transparent,
      child: InkWell(onTap: onTap, child: _content(context)),
    );
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

    // See StockTile: a name squeezed beside the numbers is cut mid-word, so
    // below a comfortable width it takes a line of its own.
    final nameBelow = space < StockTile.comfortableNameWidth;
    final name = _NameLine(
      name: row.shortName,
      maxLines: 3,
      fontSize: 12.5,
      color: colors.textName,
      chip: CategoryChip.maybe(row.category, dense: nameBelow),
      showChip: space >= StockTile.comfortableNameWidth || nameBelow,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                    if (!nameBelow) ...[const SizedBox(height: 1), name],
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
              WatchlistStar(
                market: row.market,
                ticker: row.ticker,
                dense: true,
              ),
              // The link's slot is held even when a row has no URL: a row that
              // dropped it would pull its price and change 26px to the right of
              // every other row, and out from under the headings.
              if (row.googleFinanceUrl != null)
                GoogleFinanceButton(
                  url: row.googleFinanceUrl,
                  ticker: row.ticker,
                  dense: true,
                )
              else
                const SizedBox(width: StockTile.actionWidth),
            ],
          ),
          // The name on its own line, indented to sit under the ticker.
          if (nameBelow)
            Padding(
              padding: const EdgeInsets.only(left: 38 + 12, top: 2),
              child: name,
            ),
        ],
      ),
    );
  }
}

/// A company name with the instrument's category chip beside it.
///
/// One widget for both tiles, and for both places the name can land: beside
/// the numbers when the row is wide, or on a line of its own when it is not.
///
/// A [Wrap] rather than a [Row]. A Row lays its inflexible children out
/// first and gives a `Flexible` only what is left, so when the chip alone is
/// wider than the line — 320dp at 1.3x text, with a label like "Industrial
/// Metals" — the leftover is negative and the row overflows however flexible
/// the name is. Wrapping drops the chip to the next line instead: a few
/// pixels of extra height, and nothing is ever clipped.
class _NameLine extends StatelessWidget {
  const _NameLine({
    required this.name,
    required this.maxLines,
    required this.fontSize,
    required this.color,
    required this.chip,
    required this.showChip,
  });

  final String name;
  final int maxLines;
  final double fontSize;
  final Color color;

  /// Null for every row of a file that publishes no category, which is most
  /// of them: only the ASX ETFs are labelled.
  final Widget? chip;

  /// False where the row is too tight to give the chip room without eating
  /// the name.
  final bool showChip;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: color,
      ),
    );
    if (chip == null || !showChip) return text;

    return Wrap(
      spacing: 6,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [text, chip!],
    );
  }
}
