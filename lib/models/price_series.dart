import 'growth_window.dart';
import 'stock_row.dart';

/// A single known price for a ticker on a given date.
class PricePoint {
  const PricePoint({
    required this.date,
    required this.price,
    required this.sourceWindow,
    required this.isEndpoint,
  });

  final DateTime date;
  final double price;

  /// The window table this price was read from.
  final GrowthWindow sourceWindow;

  /// True for the window's closing price, false for a window's opening price.
  final bool isEndpoint;
}

/// The price path the published data actually supports.
///
/// The screener databases do not store daily bars — each row holds only the
/// opening and closing price of its window. A ticker present in several
/// windows therefore yields one known price per window start, plus the closing
/// price shared by all of them. [build] assembles exactly those points and
/// nothing else, so the chart never interpolates prices the dataset does not
/// contain.
class PriceSeries {
  const PriceSeries(this.points);

  final List<PricePoint> points;

  bool get isEmpty => points.isEmpty;
  bool get hasShape => points.length >= 2;

  double get minPrice =>
      points.map((p) => p.price).reduce((a, b) => a < b ? a : b);

  double get maxPrice =>
      points.map((p) => p.price).reduce((a, b) => a > b ? a : b);

  DateTime get firstDate => points.first.date;
  DateTime get lastDate => points.last.date;

  /// Builds the series visible for [selected], using every window that starts
  /// inside it.
  ///
  /// Points are keyed by date. Longer windows are laid down first so that when
  /// two windows report a price for the same date, the shorter (more recent,
  /// more precise) window wins. The closing point always comes from [selected]
  /// itself, because each window publishes its own closing price and they can
  /// differ slightly.
  static PriceSeries build(Iterable<StockRow> rows, GrowthWindow selected) {
    final byWindow = <GrowthWindow, StockRow>{};
    for (final row in rows) {
      byWindow[row.window] = row;
    }

    final anchor = byWindow[selected];
    if (anchor == null) return const PriceSeries([]);

    final byDate = <DateTime, PricePoint>{};

    final relevant =
        GrowthWindow.values
            .where((w) => w.approximateDays <= selected.approximateDays)
            .toList()
          ..sort((a, b) => b.approximateDays.compareTo(a.approximateDays));

    for (final window in relevant) {
      final row = byWindow[window];
      if (row == null) continue;
      final start = _parseDate(row.firstDate);
      if (start == null) continue;
      byDate[start] = PricePoint(
        date: start,
        price: row.firstPrice,
        sourceWindow: window,
        isEndpoint: false,
      );
    }

    final end = _parseDate(anchor.lastDate);
    if (end != null) {
      byDate[end] = PricePoint(
        date: end,
        price: anchor.latestPrice,
        sourceWindow: selected,
        isEndpoint: true,
      );
    }

    final points = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return PriceSeries(points);
  }

  static DateTime? _parseDate(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }
}
