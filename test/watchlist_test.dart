import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/ui/screens/stock_detail_screen.dart';
import 'package:screener/ui/widgets/stock_tile.dart';
import 'package:screener/ui/widgets/watchlist_star.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// Starring from a list row, and what that leaves behind.
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
    cacheDir = await Directory.systemTemp.createTemp('screener_star_cache');
    serveDir = await Directory.systemTemp.createTemp('screener_star_serve');
    payloads = await buildFixturePayloads(serveDir);
  });

  tearDown(() async {
    for (final dir in [cacheDir, serveDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  /// The star inside the dashboard row for [ticker].
  Finder starFor(String ticker) => find.descendant(
    of: find.ancestor(of: find.text(ticker), matching: find.byType(GainerTile)),
    matching: find.byType(WatchlistStar),
  );

  testWidgets('a list row stars without opening the row', (tester) async {
    final prefs = await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
    );

    await tester.tap(starFor('MRNA'));
    await settle(tester);

    expect(
      find.byType(StockDetailScreen),
      findsNothing,
      reason: 'the star must not also open the row',
    );
    expect(prefs.getStringList('watchlist'), ['us:MRNA']);
  });

  testWidgets('a star from a list row reaches the watchlist', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    await tester.tap(starFor('MRNA'));
    await settle(tester);

    await tester.tap(find.text('Watchlist').last);
    await settle(tester);
    expect(find.text('MRNA'), findsWidgets);
    expect(find.text('Nothing on the watchlist'), findsNothing);
  });

  testWidgets('tapping the star again unstars it', (tester) async {
    final prefs = await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
    );

    await tester.tap(starFor('MRNA'));
    await settle(tester);
    expect(prefs.getStringList('watchlist'), ['us:MRNA']);

    await tester.tap(starFor('MRNA'));
    await settle(tester);
    expect(prefs.getStringList('watchlist'), isEmpty);
  });

  testWidgets('the star survives a restart', (tester) async {
    final prefs = await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
    );
    await tester.tap(starFor('MRNA'));
    await settle(tester);

    // Rebuilding the whole app is as close as a widget test gets to a cold
    // start: the controller reads the same store again from scratch.
    await tester.pumpWidget(const SizedBox.shrink());
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    expect(prefs.getStringList('watchlist'), ['us:MRNA']);
    await tester.tap(find.text('Watchlist').last);
    await settle(tester);
    expect(find.text('MRNA'), findsWidgets);
  });

  testWidgets('the star is keyed by market, not by ticker alone', (
    tester,
  ) async {
    final prefs = await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
    );

    await tester.tap(starFor('MRNA'));
    await tester.tap(starFor('QETH'));
    await settle(tester);

    expect(prefs.getStringList('watchlist'), ['asx:QETH', 'us:MRNA']);
  });
}
