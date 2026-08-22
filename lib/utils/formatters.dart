import 'package:intl/intl.dart';

/// Display formatting shared by every screen.
class Fmt {
  const Fmt._();

  static final NumberFormat _integer = NumberFormat('#,##0');
  static final NumberFormat _ratio = NumberFormat('0.00');
  static final DateFormat _long = DateFormat('MMM d, yyyy');
  static final DateFormat _short = DateFormat('MMM d');
  static final DateFormat _time = DateFormat('h:mm a');

  /// Formats a price with thousands separators.
  ///
  /// `NumberFormat` rounds half to even, which is not what a price list is
  /// expected to do, so the value is fixed to its decimals first — Dart rounds
  /// half away from zero there — and the grouping is applied afterwards. Prices
  /// below a cent keep four decimals to stay meaningful.
  static String price(double value) {
    final decimals = value != 0 && value.abs() < 0.1 ? 4 : 2;
    return _group(value.toStringAsFixed(decimals));
  }

  /// Inserts thousands separators into an already-fixed decimal string.
  static String _group(String fixed) {
    final negative = fixed.startsWith('-');
    final body = negative ? fixed.substring(1) : fixed;
    final dot = body.indexOf('.');
    final whole = dot == -1 ? body : body.substring(0, dot);
    final fraction = dot == -1 ? '' : body.substring(dot);

    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
      buffer.write(whole[i]);
    }
    return '${negative ? '-' : ''}$buffer$fraction';
  }

  static String signedPrice(double value) =>
      '${value >= 0 ? '+' : '-'}${price(value.abs())}';

  static String percent(double value, {int decimals = 2}) =>
      '${value.toStringAsFixed(decimals)}%';

  static String signedPercent(double value, {int decimals = 2}) =>
      '${value >= 0 ? '+' : '-'}${value.abs().toStringAsFixed(decimals)}%';

  static String integer(num value) => _integer.format(value);

  static String ratio(double value) => _ratio.format(value);

  /// Volumes are large and only need two significant digits of scale.
  static String compact(double value) {
    final abs = value.abs();
    if (abs >= 1e12) return '${(value / 1e12).toStringAsFixed(2)}T';
    if (abs >= 1e9) return '${(value / 1e9).toStringAsFixed(2)}B';
    if (abs >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
    if (abs >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
    return _integer.format(value);
  }

  static String bytes(int value) {
    if (value >= 1 << 20) return '${(value / (1 << 20)).toStringAsFixed(1)} MB';
    if (value >= 1 << 10) return '${(value / (1 << 10)).toStringAsFixed(0)} KB';
    return '$value B';
  }

  /// `2026-08-21` -> `Aug 21, 2026`, falling back to the raw text.
  static String date(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '—';
    final parsed = DateTime.tryParse(isoDate);
    return parsed == null ? isoDate : _long.format(parsed);
  }

  static String shortDate(DateTime date) => _short.format(date);

  static String dateTime(DateTime value) =>
      '${_long.format(value)}, ${_time.format(value)}';

  /// "Today, 9:30 AM" style stamp used by the Recent Analyses list.
  static String relativeStamp(DateTime value, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final day = DateTime(value.year, value.month, value.day);
    final today = DateTime(reference.year, reference.month, reference.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today, ${_time.format(value)}';
    if (diff == 1) return 'Yesterday, ${_time.format(value)}';
    if (diff < 7) return '$diff days ago';
    return _long.format(value);
  }

  /// Coverage and observation ratios are published as 0..1.
  static String coverage(double value) {
    if (value <= 0) return '—';
    if (value == 1) return '1.00';
    return _ratio.format(value);
  }
}
