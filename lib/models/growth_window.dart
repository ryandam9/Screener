/// A screener look-back window.
///
/// The published databases hold one table per window, named with a shared
/// prefix and one of these suffixes (`us_stocks_growth_7_days`,
/// `asx_etf_growth_1_year`, ...).
enum GrowthWindow {
  sevenDays(
    label: '7D',
    longLabel: '7 Day',
    tableSuffix: '_7_days',
    approximateDays: 7,
  ),
  oneMonth(
    label: '1M',
    longLabel: '1 Month',
    tableSuffix: '_1_month',
    approximateDays: 31,
  ),
  threeMonths(
    label: '3M',
    longLabel: '3 Month',
    tableSuffix: '_3_months',
    approximateDays: 92,
  ),
  sixMonths(
    label: '6M',
    longLabel: '6 Month',
    tableSuffix: '_6_months',
    approximateDays: 183,
  ),
  oneYear(
    label: '1Y',
    longLabel: '1 Year',
    tableSuffix: '_1_year',
    approximateDays: 365,
  );

  const GrowthWindow({
    required this.label,
    required this.longLabel,
    required this.tableSuffix,
    required this.approximateDays,
  });

  /// Compact label used on period pills, e.g. `7D`.
  final String label;

  /// Expanded label used in headings, e.g. `7 Day`.
  final String longLabel;

  /// Suffix that identifies the window's table inside a market database.
  final String tableSuffix;

  /// Nominal span, used only for ordering windows shortest to longest.
  final int approximateDays;

  /// Matches a physical table name to the window it holds.
  ///
  /// Returns null for tables that are not per-window growth tables, such as
  /// `consistent_growth_stocks`.
  static GrowthWindow? fromTableName(String tableName) {
    final lower = tableName.toLowerCase();
    for (final window in values) {
      if (lower.endsWith(window.tableSuffix)) return window;
    }
    return null;
  }

  static GrowthWindow? fromLabel(String? label) {
    for (final window in values) {
      if (window.label == label) return window;
    }
    return null;
  }

  /// Windows no longer than this one, shortest first.
  Iterable<GrowthWindow> get upToThis =>
      values.where((w) => w.approximateDays <= approximateDays);
}
