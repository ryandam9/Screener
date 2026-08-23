/// One weekly bar from the published price-history table.
///
/// The pipeline writes every column as TEXT — prices and volume included — so
/// each numeric field is parsed rather than cast.
class PriceBar {
  const PriceBar({
    required this.date,
    required this.ticker,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.adjClose,
    required this.volume,
    this.growthPeriods = const [],
  });

  final DateTime date;
  final String ticker;
  final double open;
  final double high;
  final double low;
  final double close;
  final double adjClose;
  final double volume;

  /// Windows this ticker qualified for, e.g. `[1Y, 6M, 3M, 1M, 5D]`.
  final List<String> growthPeriods;

  /// The value the charts plot: the adjusted close where one is published,
  /// otherwise the close.
  double get plotPrice => adjClose > 0 ? adjClose : close;

  static PriceBar? fromMap(Map<String, Object?> map) {
    final date = DateTime.tryParse(_string(map['stock_price_date']) ?? '');
    if (date == null) return null;

    final close = _double(map['close']);
    // A bar with no price cannot be plotted; the pipeline has published none,
    // but a malformed row must not become a zero-price spike on the chart.
    if (close <= 0 && _double(map['adj_close']) <= 0) return null;

    return PriceBar(
      date: date,
      ticker: _string(map['ticker']) ?? '',
      open: _double(map['open']),
      high: _double(map['high']),
      low: _double(map['low']),
      close: close,
      adjClose: _double(map['adj_close']),
      volume: _double(map['volume']),
      growthPeriods: _periods(map['growth_periods']),
    );
  }

  static List<String> _periods(Object? value) {
    final text = _string(value);
    if (text == null) return const [];
    return [
      for (final part in text.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }
}

/// A market-wide growth curve: one point per week.
class GrowthPoint {
  const GrowthPoint({required this.date, required this.pctChange});

  final DateTime date;

  /// Median percentage change since the start of the series, across tickers.
  final double pctChange;
}
