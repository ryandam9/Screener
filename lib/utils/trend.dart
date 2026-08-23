import '../models/stock_row.dart';

enum TrendLabel {
  accelerating('Accelerating'),
  steady('Steady'),
  cooling('Cooling'),
  undetermined('One window');

  const TrendLabel(this.label);
  final String label;
}

/// How a ticker's recent growth rate compares with its longest window.
class TrendAssessment {
  const TrendAssessment({
    required this.label,
    required this.shortRatePerDay,
    required this.longRatePerDay,
    required this.description,
  });

  final TrendLabel label;

  /// Percentage points gained per covered day in the shortest window.
  final double shortRatePerDay;

  /// The same rate over the longest window available.
  final double longRatePerDay;

  final String description;
}

/// Compares the per-day growth rate of the shortest and longest windows.
///
/// The windows cover very different spans, so their raw percentages are not
/// comparable — dividing each by the days it covers puts them on one scale.
/// A short window running hotter than the long one is momentum building.
TrendAssessment assessTrend(List<StockRow> rows) {
  if (rows.length < 2) {
    return const TrendAssessment(
      label: TrendLabel.undetermined,
      shortRatePerDay: 0,
      longRatePerDay: 0,
      description: 'Only one window covers this ticker.',
    );
  }

  final sorted = [...rows]
    ..sort(
      (a, b) => a.window.approximateDays.compareTo(b.window.approximateDays),
    );
  final shortest = sorted.first;
  final longest = sorted.last;

  double rate(StockRow row) {
    final days = row.daysCovered > 0
        ? row.daysCovered
        : row.window.approximateDays;
    return days <= 0 ? 0 : row.pctChange / days;
  }

  final shortRate = rate(shortest);
  final longRate = rate(longest);

  if (longRate <= 0) {
    return TrendAssessment(
      label: TrendLabel.undetermined,
      shortRatePerDay: shortRate,
      longRatePerDay: longRate,
      description:
          'The ${longest.window.longLabel.toLowerCase()} window has no positive '
          'baseline to compare against.',
    );
  }

  final ratio = shortRate / longRate;
  final TrendLabel label;
  if (ratio >= 1.25) {
    label = TrendLabel.accelerating;
  } else if (ratio <= 0.75) {
    label = TrendLabel.cooling;
  } else {
    label = TrendLabel.steady;
  }

  final multiple = ratio >= 1
      ? '${ratio.toStringAsFixed(1)}x faster than'
      : '${(1 / ratio).toStringAsFixed(1)}x slower than';

  return TrendAssessment(
    label: label,
    shortRatePerDay: shortRate,
    longRatePerDay: longRate,
    description:
        '${shortest.window.label} is gaining $multiple its '
        '${longest.window.label} pace, per covered day.',
  );
}
