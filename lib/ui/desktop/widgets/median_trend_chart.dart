import 'package:flutter/material.dart';

import '../../../models/market.dart';
import '../../../models/price_bar.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';

/// One market's growth curve.
class TrendSeries {
  const TrendSeries({
    required this.label,
    required this.color,
    required this.points,
  });

  final String label;
  final Color color;
  final List<GrowthPoint> points;
}

/// Market trend over the published year, one line per market.
///
/// Each point is the median percentage change since each ticker's own first
/// weekly bar, so the curve tracks how the constituents moved rather than the
/// price level of the largest of them. Points sit at their real dates.
class MarketTrendChart extends StatelessWidget {
  const MarketTrendChart({super.key, required this.series, this.height = 236});

  final Map<Market, List<GrowthPoint>> series;
  final double height;

  static const _usColor = Color(0xFF3B72E8);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final lines = <TrendSeries>[
      for (final market in Market.values)
        if ((series[market] ?? const []).isNotEmpty)
          TrendSeries(
            label: '${market.label} (median)',
            color: market == Market.asx ? colors.positive : _usColor,
            points: series[market]!,
          ),
    ];

    if (lines.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No weekly history published',
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
            for (final line in lines)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: line.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    line.label,
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
              lines: lines,
              gridColor: colors.chartGrid,
              labelColor: colors.textTertiary,
              zeroColor: colors.textTertiary,
              textDirection: Directionality.of(context),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Median change since each ticker’s first published week, from the '
          'weekly bars in the databases.',
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
    required this.lines,
    required this.gridColor,
    required this.labelColor,
    required this.zeroColor,
    required this.textDirection,
  });

  final List<TrendSeries> lines;
  final Color gridColor;
  final Color labelColor;
  final Color zeroColor;
  final TextDirection textDirection;

  static const _leftPadding = 46.0;
  static const _rightPadding = 12.0;
  static const _topPadding = 10.0;
  static const _bottomPadding = 26.0;
  static const _gridLines = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - _leftPadding - _rightPadding;
    final plotHeight = size.height - _topPadding - _bottomPadding;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    var minPct = 0.0;
    var maxPct = 0.0;
    var firstMs = lines.first.points.first.date.millisecondsSinceEpoch;
    var lastMs = firstMs;
    for (final line in lines) {
      for (final point in line.points) {
        if (point.pctChange < minPct) minPct = point.pctChange;
        if (point.pctChange > maxPct) maxPct = point.pctChange;
        final ms = point.date.millisecondsSinceEpoch;
        if (ms < firstMs) firstMs = ms;
        if (ms > lastMs) lastMs = ms;
      }
    }
    if (maxPct <= minPct) maxPct = minPct + 1;
    maxPct += (maxPct - minPct) * 0.12;
    final pctSpan = maxPct - minPct;
    final msSpan = (lastMs - firstMs) == 0 ? 1 : lastMs - firstMs;

    double xFor(DateTime date) =>
        _leftPadding +
        plotWidth * ((date.millisecondsSinceEpoch - firstMs) / msSpan);
    double yFor(double pct) =>
        _topPadding + plotHeight * (1 - (pct - minPct) / pctSpan);

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
        Fmt.signedPercent(maxPct - pctSpan * t, decimals: 0),
        Offset(_leftPadding - 8, y - 7),
        alignRight: true,
      );
    }

    // The zero line is the reference the whole chart is read against.
    if (minPct < 0 && maxPct > 0) {
      final y = yFor(0);
      canvas.drawLine(
        Offset(_leftPadding, y),
        Offset(size.width - _rightPadding, y),
        Paint()
          ..color = zeroColor.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }

    for (final line in lines) {
      if (line.points.length < 2) continue;
      final path = Path();
      for (var i = 0; i < line.points.length; i++) {
        final offset = Offset(
          xFor(line.points[i].date),
          yFor(line.points[i].pctChange),
        );
        if (i == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      // Mark only the latest point; a dot per week would be noise.
      final last = line.points.last;
      canvas
        ..drawCircle(
          Offset(xFor(last.date), yFor(last.pctChange)),
          4,
          Paint()..color = line.color,
        )
        ..drawCircle(
          Offset(xFor(last.date), yFor(last.pctChange)),
          1.8,
          Paint()..color = const Color(0xFFFFFFFF),
        );
    }

    _paintDates(canvas, size, firstMs, msSpan, xFor);
  }

  void _paintDates(
    Canvas canvas,
    Size size,
    int firstMs,
    int msSpan,
    double Function(DateTime) xFor,
  ) {
    const labels = 5;
    final y = size.height - _bottomPadding + 8;
    for (var i = 0; i < labels; i++) {
      final ms = firstMs + (msSpan * i / (labels - 1)).round();
      final date = DateTime.fromMillisecondsSinceEpoch(ms);
      final x = xFor(date);
      _text(
        canvas,
        Fmt.shortDate(date),
        Offset(x, y),
        centre: true,
        maxX: size.width - _rightPadding,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset, {
    bool centre = false,
    bool alignRight = false,
    double? maxX,
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
    if (maxX != null) dx = dx.clamp(0.0, maxX - painter.width);
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.lines != lines || old.gridColor != gridColor;
}
