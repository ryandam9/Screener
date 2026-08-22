import 'growth_window.dart';
import 'market.dart';

/// One row of a per-window growth table.
///
/// Column names mirror the published schema exactly; every field is decoded
/// defensively because SQLite columns are declared `FLOAT`/`INTEGER` but carry
/// whatever the writer put in them.
class StockRow {
  const StockRow({
    required this.market,
    required this.window,
    required this.ticker,
    required this.name,
    required this.exchange,
    required this.assetType,
    required this.firstDate,
    required this.firstPrice,
    required this.lastDate,
    required this.latestPrice,
    required this.pctChange,
    required this.observations,
    required this.daysCovered,
    required this.coverage,
    required this.observationRatio,
    required this.medianVolume,
    required this.priceBasis,
    required this.dataAsOf,
    required this.runId,
    required this.googleFinanceUrl,
  });

  final Market market;
  final GrowthWindow window;
  final String ticker;
  final String name;
  final String exchange;
  final String assetType;
  final String? firstDate;
  final double firstPrice;
  final String? lastDate;
  final double latestPrice;

  /// Percentage change across the window, as published (already a percentage).
  final double pctChange;

  final int observations;
  final int daysCovered;

  /// Share of the window's calendar span that has data, 0..1.
  final double coverage;

  /// Share of expected trading days that produced an observation, 0..1.
  final double observationRatio;

  final double medianVolume;
  final String priceBasis;
  final String? dataAsOf;
  final String? runId;
  final String? googleFinanceUrl;

  /// Absolute price move over the window.
  double get priceChange => latestPrice - firstPrice;

  bool get isPositive => pctChange >= 0;

  /// Identity of a ticker within the whole app (a ticker can appear in both
  /// markets, so the market is part of the key).
  String get key => '${market.id}:$ticker';

  /// Short company name with the exchange's boilerplate suffix removed, so
  /// list rows stay readable: "Moderna, Inc. - Common Stock" -> "Moderna, Inc."
  String get shortName {
    final dash = name.indexOf(' - ');
    if (dash > 0) return name.substring(0, dash);
    return name;
  }

  static StockRow fromMap(
    Map<String, Object?> map, {
    required Market market,
    required GrowthWindow window,
  }) {
    return StockRow(
      market: market,
      window: window,
      ticker: _string(map['ticker']) ?? '',
      name: _string(map['name']) ?? _string(map['ticker']) ?? '',
      exchange: _string(map['exchange']) ?? '',
      assetType: _string(map['asset_type']) ?? '',
      firstDate: _string(map['first_date']),
      firstPrice: _double(map['first_price']),
      lastDate: _string(map['last_date']),
      latestPrice: _double(map['latest_price']),
      pctChange: _double(map['pct_change']),
      observations: _int(map['observations']),
      daysCovered: _int(map['days_covered']),
      coverage: _double(map['coverage']),
      observationRatio: _double(map['observation_ratio']),
      medianVolume: _double(map['median_volume']),
      priceBasis: _string(map['price_basis']) ?? '',
      dataAsOf: _string(map['data_as_of']),
      runId: _string(map['run_id']),
      googleFinanceUrl: _string(map['google_finance']),
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// A row of `consistent_growth_stocks` — tickers that grew across every window.
class ConsistentStock {
  const ConsistentStock({
    required this.market,
    required this.ticker,
    required this.name,
    required this.exchange,
    required this.pctChangeShortestWindow,
    required this.dataAsOf,
  });

  final Market market;
  final String ticker;
  final String name;
  final String exchange;
  final double pctChangeShortestWindow;
  final String? dataAsOf;

  String get shortName {
    final dash = name.indexOf(' - ');
    if (dash > 0) return name.substring(0, dash);
    return name;
  }

  static ConsistentStock fromMap(
    Map<String, Object?> map, {
    required Market market,
  }) {
    return ConsistentStock(
      market: market,
      ticker: StockRow._string(map['ticker']) ?? '',
      name:
          StockRow._string(map['name']) ??
          StockRow._string(map['ticker']) ??
          '',
      exchange: StockRow._string(map['exchange']) ?? '',
      pctChangeShortestWindow: StockRow._double(
        map['pct_change_shortest_window'],
      ),
      dataAsOf: StockRow._string(map['data_as_of']),
    );
  }
}
