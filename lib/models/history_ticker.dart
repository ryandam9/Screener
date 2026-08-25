import 'price_bar.dart';

/// One instrument in the whole-market price history the ASX file publishes.
///
/// The growth tables only carry what passed a screen; this table carries every
/// ticker the run collected, whether it moved or not, which is what makes it
/// worth its own page.
class HistoryTicker {
  const HistoryTicker({
    required this.ticker,
    required this.name,
    required this.bars,
    required this.firstDate,
    required this.lastDate,
    required this.firstPrice,
    required this.lastPrice,
    required this.low,
    required this.high,
  });

  final String ticker;

  /// The company name where the file publishes one, otherwise null: most
  /// tickers here never reached a growth table, which is where names live.
  final String? name;

  /// How many bars the history holds for this ticker.
  final int bars;

  final DateTime firstDate;
  final DateTime lastDate;
  final double firstPrice;
  final double lastPrice;
  final double low;
  final double high;

  /// Percentage change across the published history.
  double get pctChange =>
      firstPrice > 0 ? (lastPrice / firstPrice - 1) * 100 : 0;

  bool get isPositive => pctChange >= 0;

  /// What a list row shows under the ticker.
  String get subtitle => name ?? '$bars bars';

  /// Folds the ordered bars of one ticker into its summary.
  ///
  /// Built in Dart rather than SQL: first and last value per group needs
  /// window functions, and the SQLite that ships with older Android releases
  /// does not have them.
  static HistoryTicker? fromBars(
    String ticker,
    List<PriceBar> bars, {
    String? name,
  }) {
    if (bars.isEmpty) return null;
    var low = bars.first.plotPrice;
    var high = bars.first.plotPrice;
    for (final bar in bars) {
      if (bar.plotPrice < low) low = bar.plotPrice;
      if (bar.plotPrice > high) high = bar.plotPrice;
    }
    return HistoryTicker(
      ticker: ticker,
      name: name,
      bars: bars.length,
      firstDate: bars.first.date,
      lastDate: bars.last.date,
      firstPrice: bars.first.plotPrice,
      lastPrice: bars.last.plotPrice,
      low: low,
      high: high,
    );
  }
}
