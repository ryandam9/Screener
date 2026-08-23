import 'package:flutter/material.dart';

import '../../models/price_bar.dart';
import '../../models/price_series.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// One plotted price. The chart takes these rather than a concrete row type so
/// it can draw the weekly history or, for a file that predates it, the window
/// endpoints.
class ChartPoint {
  const ChartPoint({
    required this.date,
    required this.price,
    required this.caption,
  });

  final DateTime date;
  final double price;

  /// Second line of the tooltip, e.g. `weekly close` or `7D open`.
  final String caption;

  /// The published weekly bars, which is what the app plots when the file
  /// carries price history.
  static List<ChartPoint> fromBars(Iterable<PriceBar> bars) => [
    for (final bar in bars)
      ChartPoint(date: bar.date, price: bar.plotPrice, caption: 'weekly close'),
  ];

  /// Fallback for files published before the history table existed.
  static List<ChartPoint> fromSeries(PriceSeries series) => [
    for (final point in series.points)
      ChartPoint(
        date: point.date,
        price: point.price,
        caption: point.isEndpoint
            ? 'close'
            : '${point.sourceWindow.label} open',
      ),
  ];
}

/// The price chart on the stock detail screen.
///
/// Points are plotted at their real dates, so a gap in the weekly series shows
/// as a longer segment rather than being evenly spaced away.
class PriceChart extends StatefulWidget {
  const PriceChart({
    super.key,
    required this.points,
    required this.lineColor,
    this.height = 210,
  });

  final List<ChartPoint> points;
  final Color lineColor;
  final double height;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? _selectedIndex;

  static const _leftPadding = 8.0;
  static const _rightPadding = 46.0;
  static const _topPadding = 12.0;
  static const _bottomPadding = 26.0;

  void _handlePointer(Offset position, Size size) {
    final points = widget.points;
    if (points.length < 2) return;
    final usableWidth = size.width - _leftPadding - _rightPadding;
    if (usableWidth <= 0) return;

    // Pick the point nearest the pointer along the real date axis.
    final first = points.first.date.millisecondsSinceEpoch;
    final last = points.last.date.millisecondsSinceEpoch;
    final span = (last - first) == 0 ? 1 : last - first;
    final relative = ((position.dx - _leftPadding) / usableWidth).clamp(
      0.0,
      1.0,
    );
    final target = first + span * relative;

    var index = 0;
    var best = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = (points[i].date.millisecondsSinceEpoch - target)
          .abs()
          .toDouble();
      if (distance < best) {
        best = distance;
        index = i;
      }
    }
    if (index != _selectedIndex) setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final points = widget.points;

    if (points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            points.isEmpty
                ? 'No prices published for this window'
                : 'Only one price in this window',
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _handlePointer(details.localPosition, size),
            onHorizontalDragStart: (details) =>
                _handlePointer(details.localPosition, size),
            onHorizontalDragUpdate: (details) =>
                _handlePointer(details.localPosition, size),
            onHorizontalDragEnd: (_) => setState(() => _selectedIndex = null),
            onTapCancel: () => setState(() => _selectedIndex = null),
            child: CustomPaint(
              size: size,
              painter: _PriceChartPainter(
                points: points,
                lineColor: widget.lineColor,
                gridColor: colors.chartGrid,
                labelColor: colors.textTertiary,
                tooltipBackground: colors.textPrimary,
                tooltipForeground: colors.card,
                selectedIndex: _selectedIndex,
                textDirection: Directionality.of(context),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  _PriceChartPainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.tooltipBackground,
    required this.tooltipForeground,
    required this.selectedIndex,
    required this.textDirection,
  });

  final List<ChartPoint> points;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final Color tooltipBackground;
  final Color tooltipForeground;
  final int? selectedIndex;
  final TextDirection textDirection;

  static const _leftPadding = _PriceChartState._leftPadding;
  static const _rightPadding = _PriceChartState._rightPadding;
  static const _topPadding = _PriceChartState._topPadding;
  static const _bottomPadding = _PriceChartState._bottomPadding;
  static const _gridLines = 4;

  /// A dot per point reads well for a handful of prices and turns into noise
  /// for a year of weekly ones.
  static const _maxDots = 14;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final plotWidth = size.width - _leftPadding - _rightPadding;
    final plotHeight = size.height - _topPadding - _bottomPadding;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    var rawMin = points.first.price;
    var rawMax = points.first.price;
    for (final point in points) {
      if (point.price < rawMin) rawMin = point.price;
      if (point.price > rawMax) rawMax = point.price;
    }
    // Pad the value axis so the line never touches the frame.
    final rawSpan = (rawMax - rawMin).abs() < 1e-9
        ? rawMax.abs() * 0.1 + 1
        : rawMax - rawMin;
    final min = rawMin - rawSpan * 0.12;
    final max = rawMax + rawSpan * 0.12;
    final span = max - min;

    final firstMs = points.first.date.millisecondsSinceEpoch;
    final lastMs = points.last.date.millisecondsSinceEpoch;
    final msSpan = (lastMs - firstMs) == 0 ? 1 : lastMs - firstMs;

    double xFor(int index) =>
        _leftPadding +
        plotWidth *
            ((points[index].date.millisecondsSinceEpoch - firstMs) / msSpan);
    double yFor(double price) =>
        _topPadding + plotHeight * (1 - (price - min) / span);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= _gridLines; i++) {
      final t = i / _gridLines;
      final y = _topPadding + plotHeight * t;
      canvas.drawLine(
        Offset(_leftPadding, y),
        Offset(_leftPadding + plotWidth, y),
        gridPaint,
      );
      _paintText(
        canvas,
        Fmt.price(max - span * t),
        Offset(_leftPadding + plotWidth + 6, y - 6),
        color: labelColor,
        fontSize: 10,
      );
    }

    final offsets = <Offset>[
      for (var i = 0; i < points.length; i++)
        Offset(xFor(i), yFor(points[i].price)),
    ];

    final area = Path()..moveTo(offsets.first.dx, _topPadding + plotHeight);
    for (final offset in offsets) {
      area.lineTo(offset.dx, offset.dy);
    }
    area
      ..lineTo(offsets.last.dx, _topPadding + plotHeight)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                lineColor.withValues(alpha: 0.26),
                lineColor.withValues(alpha: 0.02),
              ],
            ).createShader(
              Rect.fromLTWH(_leftPadding, _topPadding, plotWidth, plotHeight),
            ),
    );

    final line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final offset in offsets.skip(1)) {
      line.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (points.length <= _maxDots) {
      for (final offset in offsets) {
        canvas
          ..drawCircle(offset, 3.4, Paint()..color = lineColor)
          ..drawCircle(offset, 1.6, Paint()..color = tooltipForeground);
      }
    }

    _paintAxisDates(canvas, xFor, size);

    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < points.length) {
      _paintSelection(canvas, size, offsets[selected], points[selected]);
    }
  }

  void _paintAxisDates(Canvas canvas, double Function(int) xFor, Size size) {
    // At most four date labels, so they never collide.
    final maxLabels = points.length <= 4 ? points.length : 4;
    final y = size.height - _bottomPadding + 7;
    for (var i = 0; i < maxLabels; i++) {
      final index = maxLabels == 1
          ? 0
          : ((points.length - 1) * i / (maxLabels - 1)).round();
      final x = xFor(index);
      _paintText(
        canvas,
        Fmt.shortDate(points[index].date),
        Offset(x, y),
        color: labelColor,
        fontSize: 10,
        centreOn: x,
        maxX: size.width - _rightPadding,
      );
    }
  }

  void _paintSelection(
    Canvas canvas,
    Size size,
    Offset offset,
    ChartPoint point,
  ) {
    canvas.drawLine(
      Offset(offset.dx, _topPadding),
      Offset(offset.dx, size.height - _bottomPadding),
      Paint()
        ..color = lineColor.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(offset, 5.5, Paint()..color = lineColor);

    final painter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '${Fmt.price(point.price)}\n',
            style: TextStyle(
              fontFamily: kFontFamily,
              color: tooltipForeground,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: '${Fmt.shortDate(point.date)} · ${point.caption}',
            style: TextStyle(
              fontFamily: kFontFamily,
              color: tooltipForeground.withValues(alpha: 0.75),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
      textDirection: textDirection,
    )..layout();

    const padding = 8.0;
    final width = painter.width + padding * 2;
    final height = painter.height + padding * 1.4;
    var left = offset.dx - width / 2;
    left = left.clamp(0.0, size.width - width);
    final top = (offset.dy - height - 12).clamp(0.0, size.height - height);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = tooltipBackground.withValues(alpha: 0.94),
    );
    painter.paint(canvas, Offset(left + padding, top + padding * 0.7));
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    required double fontSize,
    double? centreOn,
    double? maxX,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: kFontFamily,
          color: color,
          fontSize: fontSize,
        ),
      ),
      textDirection: textDirection,
    )..layout();

    var dx = centreOn != null ? centreOn - painter.width / 2 : offset.dx;
    if (maxX != null) dx = dx.clamp(0.0, maxX - painter.width);
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(_PriceChartPainter old) =>
      old.points != points ||
      old.selectedIndex != selectedIndex ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor;
}
