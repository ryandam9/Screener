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
    required this.issuer,
    required this.category,
    required this.firstDate,
    required this.firstPrice,
    required this.lastDate,
    required this.latestPrice,
    required this.pctChange,
    required this.threshold,
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

  /// Who runs the fund — "Betashares", "VanEck". Published for the ASX ETF
  /// file only; null everywhere else, including every US row.
  final String? issuer;

  /// What the fund holds — "crypto", "precious metals", "fixed income".
  /// Published alongside [issuer], and null on the same rows.
  final String? category;

  final String? firstDate;
  final double firstPrice;
  final String? lastDate;
  final double latestPrice;

  /// Percentage change across the window, as published (already a percentage).
  final double pctChange;

  /// The cut-off this window's screen applied, in percent: the row is in the
  /// file because [pctChange] reached it. Null for files published before the
  /// column existed.
  final double? threshold;

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

  /// How far past the screen's cut-off this row landed, in percentage points.
  ///
  /// Null when the file publishes no threshold, so callers can tell "no margin"
  /// from "no cut-off recorded".
  double? get marginOverThreshold {
    final cutOff = threshold;
    return cutOff == null ? null : pctChange - cutOff;
  }

  bool get isPositive => pctChange >= 0;

  /// Identity of a ticker within the whole app (a ticker can appear in both
  /// markets, so the market is part of the key).
  String get key => '${market.id}:$ticker';

  /// Short company name with the exchange's boilerplate removed, so list rows
  /// stay readable: "Moderna, Inc. - Common Stock" -> "Moderna, Inc."
  ///
  /// Two thirds of the published names separate the instrument type with a
  /// dash. The rest run it straight on — "Sunshine Silver Mining & Refining
  /// Company Common Stock", "LandBridge Company LLC Class A Shares
  /// Representing Limited Liability Company Interests" — which is why the
  /// phrase itself is matched as well.
  String get shortName {
    var value = name;
    final dash = value.indexOf(' - ');
    if (dash > 0) value = value.substring(0, dash);
    value = value.replaceFirst(_instrumentSuffix, '');
    value = value.replaceFirst(_trailingSeparators, '');
    // A name that is nothing but its instrument type keeps what it had.
    return value.trim().isEmpty ? name : value.trim();
  }

  /// Where the instrument description starts, matched from the first marker to
  /// the end of the string.
  ///
  /// Every alternative names a share class or a depositary structure, never a
  /// word a company would use for itself, and each is anchored to a word
  /// boundary so "iShares" and "Betashares" are left alone.
  static final RegExp _instrumentSuffix = RegExp(
    // Either whitespace before the marker, or a closing bracket the published
    // name forgot to put a space after: "…(Delaware)Common Stock REIT".
    r'(?:(?<=\))\s*|\s+)(?:'
    // Depositary receipts, with or without the sponsor word in front (and
    // "Sponosred", which one row really does spell that way).
    r'(?:(?:Un)?[Ss]pon\w*\s+)?(?:American|Global)\s+Depositary\b'
    r'|(?:(?:Un)?[Ss]pon\w*\s+)?ADR\b'
    r'|Shares\s+of\s+Beneficial\s+Interest\b'
    r'|(?:Limited\s+)?Partner(?:ship)?\s+Interests\b'
    // Share classes, which may carry a voting qualifier: "Class A Limited
    // Voting Shares", "Class B Ordinary Shares".
    r'|Class\s+[A-Z]\s+(?:Limited\s+|Non-?\s*|Subordinate\s+)?(?:Voting\s+)?'
    r'(?:Ordinary\s+|Common\s+|Depositary\s+)?(?:Stock|Shares?|Units?)\b'
    r'|(?:Limited\s+|Non-?\s*|Subordinate\s+)?Voting\s+'
    r'(?:Ordinary\s+|Common\s+)?(?:Stock|Shares?|Units?)\b'
    r'|(?:Common|Ordinary|Preferred|Depositary)\s+(?:Stock|Shares?|Units?)\b'
    r'|(?:Common\s+)?Units\s+[Rr]epresenting\b'
    r').*$',
    caseSensitive: false,
  );

  static final RegExp _trailingSeparators = RegExp(r'[\s,;:\-–—]+$');

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
      issuer: _string(map['issuer']),
      category: _string(map['category']),
      firstDate: _string(map['first_date']),
      firstPrice: _double(map['first_price']),
      lastDate: _string(map['last_date']),
      latestPrice: _double(map['latest_price']),
      pctChange: _double(map['pct_change']),
      threshold: _doubleOrNull(map['threshold']),
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

  /// Distinguishes an absent or unreadable number from a published zero,
  /// which [_double] cannot: a 0.0% cut-off would be a real screen setting.
  static double? _doubleOrNull(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
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
    required this.issuer,
    required this.category,
    required this.pctChangeShortestWindow,
    required this.thresholdShortestWindow,
    required this.dataAsOf,
  });

  final Market market;
  final String ticker;
  final String name;
  final String exchange;

  /// See [StockRow.issuer] and [StockRow.category].
  final String? issuer;
  final String? category;

  final double pctChangeShortestWindow;

  /// The cut-off the shortest window's screen applied. See [StockRow.threshold].
  final double? thresholdShortestWindow;

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
      issuer: StockRow._string(map['issuer']),
      category: StockRow._string(map['category']),
      pctChangeShortestWindow: StockRow._double(
        map['pct_change_shortest_window'],
      ),
      thresholdShortestWindow: StockRow._doubleOrNull(
        map['threshold_shortest_window'],
      ),
      dataAsOf: StockRow._string(map['data_as_of']),
    );
  }
}
