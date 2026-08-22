/// The two datasets published to S3 by the screener pipeline.
///
/// Each market is one SQLite file in the bucket. The table names inside the two
/// files differ (`us_stocks_growth_*` vs `asx_etf_growth_*`), so nothing here
/// assumes a table layout — see [MarketDatabase] which discovers tables at
/// open time.
enum Market {
  asx(
    id: 'asx',
    label: 'ASX',
    subtitle: 'Australian Market',
    objectKey: 'asx.db',
    instrumentNoun: 'ETFs',
  ),
  us(
    id: 'us',
    label: 'US',
    subtitle: 'US Market',
    objectKey: 'us.db',
    instrumentNoun: 'stocks',
  );

  const Market({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.objectKey,
    required this.instrumentNoun,
  });

  /// Stable key used in preferences and cache file names.
  final String id;

  /// Short display name, e.g. `ASX`.
  final String label;

  /// Longer display name shown under [label].
  final String subtitle;

  /// Object name within the S3 bucket.
  final String objectKey;

  /// What the rows represent, used in copy such as "107 stocks".
  final String instrumentNoun;

  static Market? fromId(String? id) {
    for (final market in values) {
      if (market.id == id) return market;
    }
    return null;
  }
}
