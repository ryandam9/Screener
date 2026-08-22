import 'package:flutter/material.dart';

import '../../models/price_series.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// The price chart on the stock detail screen.
///
/// Every plotted point is a price the database states outright — a window's
/// opening price, or the closing price. Segments between points are drawn as
/// straight lines and labelled as such, because the dataset holds no
/// intermediate bars to curve through.
class PriceChart extends StatefulWidget {
  const PriceChart({
    super.key,
    required this.series,
    required this.lineColor,
    this.height = 210,
  });

  final PriceSeries series;
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
    final points = widget.series.points;
    if (points.length < 2) return;
    final usableWidth = size.width - _leftPadding - _rightPadding;
    if (usableWidth <= 0) return;

    final relative = (position.dx - _leftPadding) / usableWidth;
    final index = (relative * (points.length - 1)).round().clamp(
      0,
      points.length - 1,
    );
    if (index != _selectedIndex) setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final series = widget.series;

    if (!series.hasShape) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            series.isEmpty
                ? 'No price points for this window'
                : 'Only one price point in this window',
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
                series: series,
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
    required this.series,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.tooltipBackground,
    required this.tooltipForeground,
    required this.selectedIndex,
    required this.textDirection,
  });

  final PriceSeries series;
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

  @override
  void paint(Canvas canvas, Size size) {
    final points = series.points;
    if (points.length < 2) return;

    final plotWidth = size.width - _leftPadding - _rightPadding;
    final plotHeight = size.height - _topPadding - _bottomPadding;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    // Pad the value axis so the line never touches the frame.
    final rawMin = series.minPrice;
    final rawMax = series.maxPrice;
    final rawSpan = (rawMax - rawMin).abs() < 1e-9
        ? rawMax.abs() * 0.1 + 1
        : rawMax - rawMin;
    final min = rawMin - rawSpan * 0.12;
    final max = rawMax + rawSpan * 0.12;
    final span = max - min;

    double xFor(int index) =>
        _leftPadding + plotWidth * (index / (points.length - 1));
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

    // Mark each known price so it is obvious the line is interpolated between
    // a small number of real observations.
    for (final offset in offsets) {
      canvas
        ..drawCircle(offset, 3.4, Paint()..color = lineColor)
        ..drawCircle(offset, 1.6, Paint()..color = tooltipForeground);
    }

    _paintAxisDates(canvas, points, xFor, size);

    final selected = selectedIndex;
    if (selected != null && selected >= 0 && selected < points.length) {
      _paintSelection(canvas, size, offsets[selected], points[selected]);
    }
  }

  void _paintAxisDates(
    Canvas canvas,
    List<PricePoint> points,
    double Function(int) xFor,
    Size size,
  ) {
    // Show at most four date labels so they never collide.
    final maxLabels = points.length <= 4 ? points.length : 4;
    final y = size.height - _bottomPadding + 7;
    for (var i = 0; i < maxLabels; i++) {
      final index = maxLabels == 1
          ? 0
          : ((points.length - 1) * i / (maxLabels - 1)).round();
      final label = Fmt.shortDate(points[index].date);
      final x = xFor(index);
      _paintText(
        canvas,
        label,
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
    PricePoint point,
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
              color: tooltipForeground,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text:
                '${Fmt.shortDate(point.date)} · ${point.isEndpoint ? 'close' : '${point.sourceWindow.label} open'}',
            style: TextStyle(
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
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: textDirection,
    )..layout();

    var dx = centreOn != null ? centreOn - painter.width / 2 : offset.dx;
    if (maxX != null) dx = dx.clamp(0.0, maxX - painter.width);
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(_PriceChartPainter old) =>
      old.series != series ||
      old.selectedIndex != selectedIndex ||
      old.lineColor != lineColor ||
      old.gridColor != gridColor;
}
