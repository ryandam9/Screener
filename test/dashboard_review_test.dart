import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support/app_harness.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await loadAppFont();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File(
        '${File(Platform.resolvedExecutable).parent.parent.parent.parent.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then(ByteData.sublistView),
    );
    await icons.load();
  });
  for (final phone in [false, true]) {
    testWidgets('Dashboard review ${phone ? 'phone large text' : 'desktop'}', (
      tester,
    ) async {
      final cache = Directory.systemTemp.createTempSync('dashboard_cache');
      final serve = Directory.systemTemp.createTempSync('dashboard_serve');
      final payloads = (await tester.runAsync(
        () => buildFixturePayloads(serve),
      ))!;
      SharedPreferences.setMockInitialValues({'digest_enabled': true});
      debugDefaultTargetPlatformOverride = phone
          ? TargetPlatform.android
          : TargetPlatform.linux;
      try {
        if (phone) tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        await launchApp(
          tester,
          cacheDir: cache,
          payloads: payloads,
          size: phone ? const Size(390, 844) : const Size(1440, 1400),
          devicePixelRatio: 1,
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        if (Platform.environment['DASHBOARD_SHOTS'] == '1') {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File(
              'design-mockups/dashboard-${phone ? 'phone' : 'desktop'}-review.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        if (phone) {
          await tester.ensureVisible(find.text('Recent analyses'));
          await settle(tester);
          expect(tester.takeException(), isNull);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await cache.delete(recursive: true);
          await serve.delete(recursive: true);
        });
      }
    });
  }
}
