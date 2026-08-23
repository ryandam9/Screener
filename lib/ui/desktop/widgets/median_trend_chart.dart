import 'package:flutter/material.dart';

import '../../../data/market_database.dart';
import '../../../models/growth_window.dart';
import '../../../models/market.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';

/// One market's median change plotted across the windows it publishes.
class TrendSeries {
  const TrendSeries({
    required this.label,
    required this.color,
    required this.points,
  });

  final String label;
  final Color color;

  /// Median percentage change keyed by window.
  final Map<GrowthWindow, double> points;
}

/// Median growth per look-back window, one line per market.
///
/// The mockup charts a market index against calendar dates. The databases hold
/// no dated series to plot, so the x axis is the look-back window itself —
/// 7D through 1Y — and each point is that window's median percentage change.
/// It answers the same question ("is growth broad and holding up?") from data
/// that actually exists.
class MedianTrendChart extends StatelessWidget {
  const MedianTrendChart({
    super.key,
    required this.summaries,
    required this.highlighted,
    this.height = 236,
  });

  final Map<Market, MarketSummary> summaries;
  final GrowthWindow highlighted;
  final double height;

  static const _usColor = Color(0xFF3B72E8);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final series = <TrendSeries>[
      for (final market in Market.values)
        if (summaries[market] != null)
          TrendSeries(
            label: '${market.label} (median)',
            color: market == Market.asx ? colors.positive : _usColor,
            points: {
              for (final stat in summaries[market]!.stats)
                if (stat.count > 0) stat.window: stat.medianPctChange,
            },
          ),
    ];

    final hasData = series.any((s) => s.points.isNotEmpty);
    if (!hasData) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No windows with rows',
            style: TextStyle(fontSize: 13, color: colors.textTertiary),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            for (final entry in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: entry.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    entry.label,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: height,
          child: CustomPaint(
            size: Size.infinite,
            painter: _TrendPainter(
              series: series,
              highlighted: highlighted,
              gridColor: colors.chartGrid,
              labelColor: colors.textTertiary,
              highlightColor: colors.neutralSurface,
              textDirection: Directionality.of(context),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Each point is the median change of a look-back window, not a dated '
          'price series — the databases publish window endpoints only.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.series,
    required this.highlighted,
    required this.gridColor,
    required this.labelColor,
    required this.highlightColor,
    required this.textDirection,
  });

  final List<TrendSeries> series;
  final GrowthWindow highlighted;
  final Color gridColor;
  final Color labelColor;
  final Color highlightColor;
  final TextDirection textDirection;

  static const _leftPadding = 46.0;
  static const _rightPadding = 12.0;
  static const _topPadding = 10.0;
  static const _bottomPadding = 26.0;
  static const _gridLines = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final windows = GrowthWindow.values;
    final plotWidth = size.width - _leftPadding - _rightPadding;
    final plotHeight = size.height - _topPadding - _bottomPadding;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    var min = 0.0;
    var max = 0.0;
    for (final entry in series) {
      for (final value in entry.points.values) {
        if (value < min) min = value;
        if (value > max) max = value;
      }
    }
    if (max <= min) max = min + 1;
    // Head room so the top line never rides the frame.
    max += (max - min) * 0.12;

    double xFor(int index) =>
        _leftPadding + plotWidth * (index / (windows.length - 1));
    double yFor(double value) =>
        _topPadding + plotHeight * (1 - (value - min) / (max - min));

    // Column behind the window currently selected in the top bar.
    final highlightIndex = windows.indexOf(highlighted);
    if (highlightIndex >= 0) {
      final centre = xFor(highlightIndex);
      final half = plotWidth / (windows.length - 1) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            (centre - half).clamp(_leftPadding, size.width),
            _topPadding,
            (centre + half).clamp(_leftPadding, size.width),
            _topPadding + plotHeight,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = highlightColor,
      );
    }

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= _gridLines; i++) {
      final t = i / _gridLines;
      final y = _topPadding + plotHeight * t;
      canvas.drawLine(
        Offset(_leftPadding, y),
        Offset(size.width - _rightPadding, y),
        gridPaint,
      );
      _text(
        canvas,
        Fmt.signedPercent(max - (max - min) * t, decimals: 0),
        Offset(_leftPadding - 8, y - 7),
        alignRight: true,
      );
    }

    for (var i = 0; i < windows.length; i++) {
      _text(
        canvas,
        windows[i].label,
        Offset(xFor(i), size.height - _bottomPadding + 8),
        centre: true,
      );
    }

    for (final entry in series) {
      final offsets = <Offset>[];
      for (var i = 0; i < windows.length; i++) {
        final value = entry.points[windows[i]];
        if (value == null) continue;
        offsets.add(Offset(xFor(i), yFor(value)));
      }
      if (offsets.isEmpty) continue;

      if (offsets.length > 1) {
        final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
        for (final offset in offsets.skip(1)) {
          path.lineTo(offset.dx, offset.dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = entry.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      for (final offset in offsets) {
        canvas
          ..drawCircle(offset, 4, Paint()..color = entry.color)
          ..drawCircle(offset, 1.8, Paint()..color = const Color(0xFFFFFFFF));
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset, {
    bool centre = false,
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 10.5),
      ),
      textDirection: textDirection,
    )..layout();

    var dx = offset.dx;
    if (centre) dx -= painter.width / 2;
    if (alignRight) dx -= painter.width;
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.highlighted != highlighted ||
      old.gridColor != gridColor ||
      old.series != series;
}
