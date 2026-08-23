import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/ui/screens/stock_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// The handset layout, driven end to end against the fixture databases served
/// by a fake S3. The harness explains why `pumpAndSettle` cannot be used here.
void main() {
  late Directory tempDir;
  late Directory serveDir;
  late Map<String, List<int>> payloads;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // setUp runs outside the fake-async zone, so the fixtures can be written
  // here with ordinary async I/O.
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('screener_app_test');
    serveDir = await Directory.systemTemp.createTemp('screener_app_serve');
    SharedPreferences.setMockInitialValues({});
    payloads = await buildFixturePayloads(serveDir);
  });

  tearDown(() async {
    for (final dir in [tempDir, serveDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  /// Starts the app on a phone-sized surface.
  Future<void> launch(WidgetTester tester, {bool Function()? shouldFail}) =>
      launchApp(
        tester,
        cacheDir: tempDir,
        payloads: payloads,
        shouldFail: shouldFail,
      ).then((_) {});

  testWidgets('dashboard renders both markets and the top gainers', (
    tester,
  ) async {
    await launch(tester);

    expect(find.text('Stocks Analysis'), findsOneWidget);
    // Both market cards are present; their subtitles are unique to the cards,
    // where the bare labels also appear as badges on mixed-market rows.
    expect(find.text('Australian Market'), findsOneWidget);
    expect(find.text('US Market'), findsOneWidget);

    // The strongest 7-day mover across both fixture markets.
    expect(find.text('MRNA'), findsWidgets);
    expect(find.text('139.22'), findsWidgets);

    // Recent Analyses is built from the run metadata inside the files.
    expect(find.text('Recent Analyses'), findsOneWidget);
    expect(find.textContaining('7 Day Analysis'), findsWidgets);
  });

  testWidgets('opening a gainer shows its detail screen', (tester) async {
    await launch(tester);

    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    expect(find.byType(StockDetailScreen), findsOneWidget);
    expect(find.text('Moderna, Inc. - Common Stock'), findsOneWidget);
    expect(find.text('First Price'), findsWidgets);

    // The stat grid sits below the chart, so scroll it into view.
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await settle(tester);
    expect(find.text('Days Cov.'), findsOneWidget);
    expect(find.text('Median Vol.'), findsOneWidget);
  });

  testWidgets('the detail screen switches windows and inner tabs', (
    tester,
  ) async {
    await launch(tester);

    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    // MRNA appears in both the 7D and 1Y fixture tables.
    await tester.tap(find.text('1Y'));
    await settle(tester);
    expect(find.textContaining('472.50%'), findsWidgets);

    await tester.tap(find.text('Metrics'));
    await settle(tester);
    expect(find.text('Key Metrics'), findsOneWidget);
    expect(find.text('Detailed Metrics'), findsOneWidget);

    await tester.tap(find.text('Windows'));
    await settle(tester);
    expect(find.text('Every window'), findsOneWidget);
  });

  testWidgets('starring a ticker fills the watchlist', (tester) async {
    await launch(tester);

    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    await tester.tap(find.byIcon(Icons.star_border_rounded));
    await settle(tester);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    // The detail screen draws its own header, not an AppBar leading button.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);

    await tester.tap(find.text('Watchlist'));
    await settle(tester);

    expect(find.textContaining('starred tickers'), findsWidgets);
    expect(find.text('MRNA'), findsWidgets);
  });

  testWidgets('the markets tab lists rows and search narrows them', (
    tester,
  ) async {
    await launch(tester);

    await tester.tap(find.text('Markets'));
    await settle(tester);

    expect(find.text('MRNA'), findsWidgets);
    expect(find.text('AMLX'), findsWidgets);

    await tester.tap(find.byTooltip('Search'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'AMLX');
    await settle(tester);

    expect(find.text('AMLX'), findsWidgets);
    expect(find.text('MRNA'), findsNothing);
  });

  testWidgets('every tab and market-list tab renders', (tester) async {
    // Any layout overflow or framework assertion fails the test, so simply
    // visiting each screen is the check.
    await launch(tester);

    await tester.tap(find.text('Analysis'));
    await settle(tester);
    expect(find.text('Run overview'), findsOneWidget);
    expect(find.text('Change distribution'), findsOneWidget);
    expect(find.text('Most traded'), findsOneWidget);

    await tester.tap(find.text('Markets'));
    await settle(tester);
    for (final tab in ['Top Movers', 'Consistent', 'Watchlist', 'All Stocks']) {
      // "Watchlist" also names a bottom-nav destination, so scope to the TabBar.
      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text(tab)),
      );
      await settle(tester);
    }

    await tester.tap(find.text('More'));
    await settle(tester);
    expect(find.text('Data sources'), findsOneWidget);
    expect(find.textContaining('us.db'), findsWidgets);
  });

  testWidgets('a failed refresh keeps serving the cached databases', (
    tester,
  ) async {
    var failing = false;
    await launch(tester, shouldFail: () => failing);
    expect(find.text('MRNA'), findsWidgets);

    failing = true;
    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Re-download'));
    await settle(tester);

    await tester.tap(find.text('Dashboard'));
    await settle(tester);

    expect(
      find.text('MRNA'),
      findsWidgets,
      reason: 'the open database must survive a failed refresh',
    );
    expect(find.textContaining('cached data'), findsWidgets);
  });
}
