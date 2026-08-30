import '../utils/formatters.dart';

/// The datasets published to S3 by the screener pipeline.
///
/// Each market is one SQLite file in the bucket. The table names inside the
/// files differ (`us_stocks_growth_*`, `asx_etf_growth_*`,
/// `nse_stocks_growth_*`), so nothing here assumes a table layout — see
/// [MarketDatabase], which discovers tables at open time by their shape.
///
/// Add a market at the end of this list, never in the middle: notification
/// ids are derived from the enum index (see [NotificationIds.digestFor]), so
/// inserting one would re-point the alerts already sitting in a user's shade.
enum Market {
  asx(
    id: 'asx',
    label: 'ASX',
    subtitle: 'Australian Market',
    longName: 'Australian Securities Exchange',
    objectKey: 'asx.db',
    instrumentNoun: 'ETFs',
    currencySymbol: r'A$',
    emoji: '🇦🇺',
  ),
  us(
    id: 'us',
    label: 'US',
    subtitle: 'US Market',
    longName: 'NASDAQ, NYSE and affiliates',
    objectKey: 'us.db',
    instrumentNoun: 'stocks',
    currencySymbol: r'$',
    emoji: '🇺🇸',
  ),
  nse(
    id: 'nse',
    label: 'NSE',
    subtitle: 'Indian Market',
    longName: 'National Stock Exchange of India',
    objectKey: 'nse.db',
    instrumentNoun: 'stocks',
    currencySymbol: '₹',
    emoji: '🇮🇳',
  );

  const Market({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.longName,
    required this.objectKey,
    required this.instrumentNoun,
    required this.currencySymbol,
    required this.emoji,
  });

  /// Stable key used in preferences and cache file names.
  final String id;

  /// Short display name, e.g. `ASX`.
  final String label;

  /// Longer display name shown under [label].
  final String subtitle;

  /// What the file actually covers, used where [subtitle] would repeat the
  /// heading above it.
  final String longName;

  /// Object name within the S3 bucket.
  final String objectKey;

  /// What the rows represent, used in copy such as "107 stocks".
  final String instrumentNoun;

  /// What prices in this file are quoted in.
  ///
  /// The files publish no currency of their own; both quote in the local one,
  /// and a plain `$` in front of an ASX price reads as US dollars.
  final String currencySymbol;

  /// Marks which file a notification is about, at a glance.
  ///
  /// Notifications have no room for a per-market icon of their own — the
  /// small icon is the app's — so the flag in the text does that job.
  final String emoji;

  /// A price with this market's currency in front, e.g. `A$19.84`.
  String money(double value) => '$currencySymbol${Fmt.price(value)}';

  static Market? fromId(String? id) {
    for (final market in values) {
      if (market.id == id) return market;
    }
    return null;
  }
}
