import 'dart:io';
import 'package:screener/ui/widgets/price_chart.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/ui/desktop/widgets/desktop_cards.dart';
import 'package:screener/ui/widgets/panels.dart';
import 'package:screener/theme/app_theme.dart';

/// The typeface is the mockups' Roboto Condensed, and it is really bundled.
///
/// A family name the pubspec does not declare is not an error in Flutter: the
/// text quietly falls back to the platform default, which is exactly the
/// "colours changed, nothing else did" result the redesign was meant to fix.
void main() {
  testWidgets('chart applies the supplied text scale once to nominal sizes', (
    tester,
  ) async {
    final scaler = _RecordingScaler();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: Scaffold(
            body: PriceChart(
              lineColor: Colors.green,
              points: [
                ChartPoint(
                  date: DateTime(2026, 1, 1),
                  price: 10,
                  caption: 'close',
                ),
                ChartPoint(
                  date: DateTime(2026, 1, 8),
                  price: 12,
                  caption: 'close',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(scaler.sizes, contains(10.0));
    expect(scaler.sizes, isNot(contains(11.5)));
    scaler.sizes.clear();
    await tester.tap(find.byType(PriceChart));
    await tester.pump();
    expect(scaler.sizes, containsAll([12.5, 10.5]));
    expect(tester.takeException(), isNull);
  });

  test('the app font is Roboto Condensed and ships at every weight used', () {
    expect(kFontFamily, 'Roboto Condensed');
    expect(AppTheme.light().textTheme.bodyMedium?.fontFamily, kFontFamily);
    expect(AppTheme.dark().textTheme.titleLarge?.fontFamily, kFontFamily);

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- family: $kFontFamily'));
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final asset = 'assets/fonts/RobotoCondensed-$weight.ttf';
      expect(pubspec, contains(asset));
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  test('the boost multiplies the reader\'s own text scale', () {
    const scaler = BoostedTextScaler(TextScaler.linear(1.3));
    expect(scaler.scale(10), closeTo(10 * kTypeScale * 1.3, 1e-9));
    expect(kTypeScale, greaterThan(1));
  });

  // A button's textStyle replaces the theme's rather than merging with it, so
  // one that sets only a size draws its label in the platform's default face.
  testWidgets('panel action buttons keep the app font', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              SectionHeader(
                title: 'Section',
                actionLabel: 'See all',
                onAction: () {},
              ),
              DesktopPanel(
                title: 'Panel',
                actionLabel: 'View all',
                onAction: () {},
                child: const SizedBox(height: 10),
              ),
            ],
          ),
        ),
      ),
    );

    for (final label in ['See all', 'View all']) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      expect(paragraph.text.style?.fontFamily, kFontFamily, reason: label);
    }
  });

  // Inter carried ▲, ▼ and →; Roboto Condensed does not, and a character the
  // bundled face lacks is drawn by whatever font the device falls back to —
  // or as an empty box. Every character the screens use must be in the font.
  test('every character the screens draw is in the bundled font', () {
    final covered = _bmpCoverage(
      File('assets/fonts/RobotoCondensed-Regular.ttf').readAsBytesSync(),
    );
    // Drawn by someone else's font, not ours: emoji (the system's emoji
    // face) and the clipboard text the detail screen copies.
    bool exempt(int rune, String path) =>
        rune >= 0x1F000 ||
        (rune == 0x2192 && path.endsWith('stock_detail_screen.dart'));

    final missing = <String>{};
    for (final file in Directory('lib/ui').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        for (final rune in line.runes) {
          if (rune < 0x80 || covered.contains(rune)) continue;
          if (exempt(rune, file.path)) continue;
          missing.add('${String.fromCharCode(rune)} in ${file.path}');
        }
      }
    }
    expect(missing, isEmpty);
  });
}

/// The Basic Multilingual Plane characters a TrueType font maps, read from
/// its cmap's format 4 subtable.
Set<int> _bmpCoverage(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final tables = data.getUint16(4);
  var cmap = -1;
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    if (String.fromCharCodes(bytes.sublist(record, record + 4)) == 'cmap') {
      cmap = data.getUint32(record + 8);
    }
  }
  final covered = <int>{};
  final subtables = data.getUint16(cmap + 2);
  for (var i = 0; i < subtables; i++) {
    final at = cmap + data.getUint32(cmap + 4 + i * 8 + 4);
    if (data.getUint16(at) != 4) continue;
    final segments = data.getUint16(at + 6) ~/ 2;
    final ends = at + 14;
    final starts = ends + segments * 2 + 2;
    final deltas = starts + segments * 2;
    final offsets = deltas + segments * 2;
    for (var s = 0; s < segments; s++) {
      final end = data.getUint16(ends + s * 2);
      final start = data.getUint16(starts + s * 2);
      final delta = data.getUint16(deltas + s * 2);
      final rangeOffset = data.getUint16(offsets + s * 2);
      for (var c = start; c <= end && c != 0xFFFF; c++) {
        int glyph;
        if (rangeOffset == 0) {
          glyph = (c + delta) & 0xFFFF;
        } else {
          final where = offsets + s * 2 + rangeOffset + (c - start) * 2;
          glyph = data.getUint16(where);
          if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
        }
        if (glyph != 0) covered.add(c);
      }
    }
  }
  return covered;
}

class _RecordingScaler extends TextScaler {
  final sizes = <double>[];
  @override
  double scale(double fontSize) {
    sizes.add(fontSize);
    return fontSize * 1.5;
  }

  @override
  double get textScaleFactor => 1.5;
}
