import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/ui/widgets/panels.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// Global search, and what it is allowed to leave out.
///
/// The screens are threshold-filtered, so searching only the selected window
/// answers a narrower question than the one people ask: `asx.db` publishes a
/// year of prices for 456 tickers and lists 8 of them in the 7-day screen.
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
    cacheDir = await Directory.systemTemp.createTemp('screener_search_cache');
    serveDir = await Directory.systemTemp.createTemp('screener_search_serve');
    payloads = await buildFixturePayloads(serveDir, historyBeyondScreens: true);
  });

  tearDown(() async {
    for (final dir in [cacheDir, serveDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  /// Opens search from the dashboard and types [term].
  Future<void> search(WidgetTester tester, String term) async {
    await tester.tap(find.byIcon(Icons.search));
    await settle(tester);
    await tester.enterText(find.byType(TextField), term);
    // The field is debounced by 220ms, so the query is not raised on the
    // keystroke that triggered it.
    await settle(tester, frames: 12);
  }

  testWidgets('a screened ticker is grouped under the current screen', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await search(tester, 'MRNA');

    expect(find.text('In the 7 day screen'), findsOneWidget);
    expect(find.text('MRNA'), findsWidgets);
    expect(find.text('In market history'), findsNothing);
  });

  testWidgets('a ticker the window does not list is found in the history', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await search(tester, 'NVAX');

    // NVAX has weekly closes and a monthly screen row, but nothing in the
    // 7-day window. The old search returned nothing at all for it.
    expect(find.text('In the 7 day screen'), findsNothing);
    expect(find.text('In market history'), findsOneWidget);
    expect(find.text('NVAX'), findsWidgets);
    expect(
      find.text('In the 1M screen'),
      findsOneWidget,
      reason: 'a result says which screen it did clear',
    );
  });

  testWidgets('a ticker in no screen at all says so', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await search(tester, 'ZZZH');

    expect(find.text('In market history'), findsOneWidget);
    expect(find.text('Not in any screen this run'), findsOneWidget);
  });

  testWidgets('a starred ticker the run dropped is still findable', (
    tester,
  ) async {
    // GONE is in no screen and no history — the run has nothing to say about
    // it — but it is starred, which is reason enough to find it.
    SharedPreferences.setMockInitialValues({
      'watchlist': ['us:GONE'],
    });
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await search(tester, 'GONE');

    expect(find.text('Watchlisted'), findsOneWidget);
    expect(find.text('GONE'), findsWidgets);
    expect(find.text('Dropped from the latest run'), findsOneWidget);
  });

  testWidgets('a ticker lands in one group, not two', (tester) async {
    SharedPreferences.setMockInitialValues({
      'watchlist': ['us:MRNA', 'us:NVAX'],
    });
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    // Screened and starred: listed under the screen, wearing its star there.
    await search(tester, 'MRNA');
    expect(find.text('In the 7 day screen'), findsOneWidget);
    expect(find.text('Watchlisted'), findsNothing);

    // In the history and starred: listed under the history, not repeated.
    await tester.enterText(find.byType(TextField), 'NVAX');
    await settle(tester, frames: 12);
    expect(find.text('In market history'), findsOneWidget);
    expect(find.text('Watchlisted'), findsNothing);
    // Scoped to the results: the search field holds the term too.
    expect(
      find.descendant(of: find.byType(Panel), matching: find.text('NVAX')),
      findsOneWidget,
    );
  });

  testWidgets('nothing matched says all three were looked at', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await search(tester, 'QQQQQQ');

    expect(find.textContaining('No matches for'), findsOneWidget);
    expect(
      find.textContaining('the price history'),
      findsOneWidget,
      reason: 'the empty state names what was searched',
    );
  });
}
