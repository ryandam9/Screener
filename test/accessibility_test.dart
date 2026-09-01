import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/theme/app_theme.dart';
import 'package:screener/ui/widgets/watchlist_star.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// Contrast ratio of [a] on [b], per WCAG 2.1.
double contrast(Color a, Color b) {
  double luminance(Color c) => c.computeLuminance();
  final high = luminance(a) > luminance(b) ? luminance(a) : luminance(b);
  final low = luminance(a) > luminance(b) ? luminance(b) : luminance(a);
  return (high + 0.05) / (low + 0.05);
}

void main() {
  late Directory cacheDir;
  late Directory serveDir;
  late Map<String, List<int>> payloads;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cacheDir = await Directory.systemTemp.createTemp('a11y_cache');
    serveDir = await Directory.systemTemp.createTemp('a11y_serve');
    payloads = await buildFixturePayloads(serveDir);
  });

  tearDown(() async {
    for (final dir in [cacheDir, serveDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  test('the smallest text clears 4.5:1 on both surfaces it sits on', () {
    for (final (name, colors) in [
      ('light', ScreenerColors.light),
      ('dark', ScreenerColors.dark),
    ]) {
      for (final (surface, label) in [
        (colors.card, 'card'),
        (colors.pageBackground, 'page'),
      ]) {
        expect(
          contrast(colors.textTertiary, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$name tertiary text on the $label',
        );
        expect(
          contrast(colors.textSecondary, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$name secondary text on the $label',
        );
      }
    }
  });

  testWidgets('a dense row action is a real tap target on a phone', (
    tester,
  ) async {
    // The icon stays its drawn size; only the target grows, so a desktop row
    // is unchanged. Tests run as Android, which is the platform that matters.
    expect(defaultTargetPlatform, TargetPlatform.android);

    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await tester.tap(find.text('Markets'));
    await settle(tester);

    final star = tester.getSize(find.byType(WatchlistStar).first);
    expect(star.width, greaterThanOrEqualTo(44));
    expect(star.height, greaterThanOrEqualTo(44));
  });
}
