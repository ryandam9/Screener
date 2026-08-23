import 'package:flutter/material.dart';

import '../../../models/stock_row.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';
import 'desktop_cards.dart';

/// The Top Gainers table: rank, ticker, company, market, price, change, % gain.
///
/// Desktop has the width for the columns the handset layout has to stack, so
/// this is a real table rather than a list of tiles.
class GainersTable extends StatelessWidget {
  const GainersTable({super.key, required this.rows, required this.onTap});

  final List<StockRow> rows;
  final ValueChanged<StockRow> onTap;

  static const _rank = 34.0;
  static const _ticker = 108.0;
  static const _market = 70.0;
  static const _price = 96.0;
  static const _change = 100.0;
  static const _gain = 92.0;

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
            ],
          ),
        ),
        Divider(height: 1, color: colors.divider),
        for (var i = 0; i < rows.length; i++) ...[
          _GainerRow(rank: i + 1, row: rows[i], onTap: () => onTap(rows[i])),
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
    required this.onTap,
  });

  final int rank;
  final StockRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget numeric(String text, double width, {Color? color}) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color ?? colors.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
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
              child: Text(
                row.shortName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
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
            ),
          ],
        ),
      ),
    );
  }
}
