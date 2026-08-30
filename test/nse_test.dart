import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/db_sync_service.dart';
import 'package:screener/models/market.dart';
import 'package:screener/services/digest_service.dart';
import 'package:screener/ui/screens/stock_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// The third published file, `nse.db`.
///
/// It arrived after the app had been built around two, so these cover the
/// places that counted rather than iterated: the bucket, the dashboard's
/// summary strip, the market list, and the money in an alert.
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
    cacheDir = await Directory.systemTemp.createTemp('screener_nse_cache');
    serveDir = await Directory.systemTemp.createTemp('screener_nse_serve');
    payloads = await buildFixturePayloads(serveDir);
  });

  tearDown(() async {
    for (final dir in [cacheDir, serveDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  test('nse.db is fetched from the same bucket as the other two', () async {
    final prefs = await SharedPreferences.getInstance();
    final service = DbSyncService(preferences: prefs);
    addTearDown(service.dispose);

    expect(service.urlFor(Market.nse).toString(), endsWith('/nse.db'));
    expect(Market.fromId('nse'), Market.nse);
    // Notification ids come off the enum index, so a market added ahead of
    // the existing two would re-point alerts already in a user's shade.
    expect(Market.values.indexOf(Market.nse), Market.values.length - 1);
  });

  testWidgets('the dashboard summarises NSE alongside the other files', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    expect(find.text('NSE'), findsWidgets);
    expect(find.text('Indian Market'), findsOneWidget);
    // The file's own rows are ranked with everyone else's.
    expect(find.text('TATAMOTORS'), findsWidgets);
  });

  testWidgets('a third card wraps rather than squeezing the headline', (
    tester,
  ) async {
    await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
      size: const Size(360, 740),
      devicePixelRatio: 1.0,
    );

    final asx = tester.getTopLeft(find.text('Australian Market'));
    final us = tester.getTopLeft(find.text('US Market'));
    final nse = tester.getTopLeft(find.text('Indian Market'));

    // Two across, then the third under the first. Side by side all three
    // would each get 108dp, which is narrower than "+117.91%".
    expect(us.dx, greaterThan(asx.dx));
    expect((us.dy - asx.dy).abs(), lessThan(1));
    expect(nse.dx, asx.dx, reason: 'the third wraps to the next row');
    expect(nse.dy, greaterThan(asx.dy));
  });

  testWidgets('the market list opens on NSE and lists its rows', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    await tester.tap(find.text('Markets').last);
    await settle(tester);
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<Market>),
        matching: find.text('NSE'),
      ),
    );
    await settle(tester);

    expect(find.text('TATAMOTORS'), findsWidgets);
    expect(find.text('Tata Motors Limited'), findsWidgets);

    await tester.tap(find.text('TATAMOTORS').first);
    await settle(tester);
    expect(find.byType(StockDetailScreen), findsOneWidget);
  });

  test('an NSE alert quotes the price in rupees', () async {
    final prefs = await SharedPreferences.getInstance();
    final notifier = FakeNotifier();
    final sync = fixtureSyncService(
      preferences: prefs,
      cacheDir: cacheDir,
      payloads: payloads,
    );
    addTearDown(sync.dispose);

    // Yesterday saw every screened ticker except the NSE one.
    await prefs.setStringList('digest_snapshot_7d', [
      'us:MRNA',
      'us:AMLX',
      'asx:QETH',
    ]);

    await DigestService(
      preferences: prefs,
      sync: sync,
      notifier: notifier,
      clock: () => DateTime(2026, 8, 24, 9),
    ).run();

    final alert = notifier.posted.firstWhere(
      (n) => n.title.contains('TATAMOTORS'),
    );
    expect(alert.title, '📈 TATAMOTORS — Tata Motors Limited');
    expect(
      alert.body,
      contains('Current price ₹1,043.60'),
      reason: 'a plain \$ in front of an NSE price reads as US dollars',
    );
  });
}
