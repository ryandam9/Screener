import 'package:flutter/material.dart';

import '../../../models/stock_row.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/google_finance_button.dart';
import '../../widgets/watchlist_star.dart';
import 'desktop_cards.dart';

/// The Top Gainers table: rank, ticker, company, market, price, change, % gain.
///
/// Desktop has the width for the columns the handset layout has to stack, so
/// this is a real table rather than a list of tiles.
class GainersTable extends StatelessWidget {
  const GainersTable({
    super.key,
    required this.rows,
    required this.onTap,
    this.selected,
  });

  final List<StockRow> rows;
  final ValueChanged<StockRow> onTap;

  /// Row currently charted below the table, marked so the link is obvious.
  final StockRow? selected;

  // The company name takes what these leave. They were wide enough that on a
  // 1280-wide window the name ellipsized to "Moder…", so they are sized to the
  // values they actually hold ("139.22", "+75.33", "+117.9%") plus a little
  // slack, not to their headings.
  static const _rank = 28.0;
  static const _ticker = 92.0;
  static const _market = 54.0;
  static const _price = 74.0;
  static const _change = 80.0;
  static const _gain = 76.0;
  static const _star = 28.0;
  static const _link = 28.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        child: Text(
          'No rows in this window.',
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
      );
    }

    Widget heading(String text, double width, {bool end = false}) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: end ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: colors.textSecondary,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Row(
            children: [
              heading('#', _rank),
              heading('Ticker', _ticker),
              const Expanded(child: SizedBox()),
              const SizedBox(width: 12),
              heading('Market', _market),
              heading('Price', _price, end: true),
              heading('Change', _change, end: true),
              heading('% Gain', _gain, end: true),
              const SizedBox(width: _star + _link),
            ],
          ),
        ),
        Divider(height: 1, color: colors.divider),
        for (var i = 0; i < rows.length; i++) ...[
          _GainerRow(
            rank: i + 1,
            row: rows[i],
            selected:
                rows[i].ticker == selected?.ticker &&
                rows[i].market == selected?.market,
            onTap: () => onTap(rows[i]),
          ),
          if (i != rows.length - 1)
            Divider(
              height: 1,
              color: colors.divider,
              indent: 18,
              endIndent: 18,
            ),
        ],
      ],
    );
  }
}

class _GainerRow extends StatelessWidget {
  const _GainerRow({
    required this.rank,
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final int rank;
  final StockRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget numeric(
      String text,
      double width, {
      Color? color,
      FontWeight weight = FontWeight.w500,
    }) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: weight,
          color: color ?? colors.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? colors.positiveSurface : null,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: GainersTable._rank,
              child: Text(
                '$rank',
                style: TextStyle(fontSize: 12.5, color: colors.textTertiary),
              ),
            ),
            SizedBox(
              width: GainersTable._ticker,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TickerChip(ticker: row.ticker),
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      row.shortName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: colors.textName,
                      ),
                    ),
                  ),
                  // Inside the name's column, not one of its own. This panel
                  // is about 700px on a 1440 window, and a fixed column wide
                  // enough for "Industrial Metals" took 124px from every row
                  // — cutting "Moderna, Inc." in half on the US rows, which
                  // have no category to show for it. Here only a labelled row
                  // pays, and it pays with a name the ticker already names.
                  if (CategoryChip.maybe(row.category, dense: true)
                      case final chip?) ...[
                    const SizedBox(width: 8),
                    chip,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: GainersTable._market,
              child: Text(
                row.market.label,
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ),
            numeric(Fmt.price(row.latestPrice), GainersTable._price),
            numeric(
              Fmt.signedPrice(row.priceChange),
              GainersTable._change,
              color: colors.forChange(row.priceChange),
            ),
            numeric(
              Fmt.signedPercent(row.pctChange, decimals: 1),
              GainersTable._gain,
              color: colors.forChange(row.pctChange),
              weight: FontWeight.w600,
            ),
            SizedBox(
              width: GainersTable._star,
              child: Align(
                alignment: Alignment.centerRight,
                child: WatchlistStar(
                  market: row.market,
                  ticker: row.ticker,
                  dense: true,
                ),
              ),
            ),
            SizedBox(
              width: GainersTable._link,
              child: row.googleFinanceUrl == null
                  ? null
                  : Align(
                      alignment: Alignment.centerRight,
                      child: GoogleFinanceButton(
                        url: row.googleFinanceUrl,
                        ticker: row.ticker,
                        dense: true,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
