import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/models/market.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// The category and issuer filters, which only the ASX file can offer: it is
/// the one that publishes the columns.
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
    cacheDir = await Directory.systemTemp.createTemp('screener_facet_cache');
    serveDir = await Directory.systemTemp.createTemp('screener_facet_serve');
    payloads = await buildFixturePayloads(serveDir, asxCategories: true);
  });

  tearDown(() async {
    for (final dir in [cacheDir, serveDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  /// Opens the market list on [market], via the sheet that hangs off the title.
  Future<void> openMarkets(WidgetTester tester, String market) async {
    await tester.tap(find.text('Markets').last);
    await settle(tester);
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<Market>),
        matching: find.text(market),
      ),
    );
    await settle(tester);
    // A SegmentedButton does not fire its callback for the segment already
    // selected, so the sheet only pops itself when the market actually
    // changed; otherwise it is dismissed here.
    if (find.byType(SegmentedButton<Market>).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
    }
  }

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.filter_list));
    await settle(tester);
  }

  testWidgets('filters the ASX list to a union of categories', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await openMarkets(tester, 'ASX');

    for (final ticker in ['QETH', 'GDX', 'ATOM']) {
      expect(find.text(ticker), findsWidgets, reason: 'unfiltered list');
    }

    await openFilters(tester);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Issuer'), findsOneWidget);
    // Published lower case, shown capitalised.
    expect(find.widgetWithText(FilterChip, 'Precious Metals'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Precious Metals'));
    await tester.tap(find.widgetWithText(FilterChip, 'Industrial Metals'));
    await settle(tester);
    await tester.tap(find.text('Apply'));
    await settle(tester);

    expect(find.text('GDX'), findsWidgets);
    expect(find.text('ATOM'), findsWidgets);
    expect(
      find.text('QETH'),
      findsNothing,
      reason: 'crypto is not one of the two chosen categories',
    );

    // Reset puts the whole list back.
    await openFilters(tester);
    await tester.tap(find.text('Reset'));
    await settle(tester);
    expect(find.text('QETH'), findsWidgets);
  });

  testWidgets('narrows further by issuer', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await openMarkets(tester, 'ASX');

    await openFilters(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'VanEck'));
    await settle(tester);
    await tester.tap(find.text('Apply'));
    await settle(tester);

    expect(find.text('GDX'), findsWidgets);
    for (final ticker in ['QETH', 'ATOM']) {
      expect(find.text(ticker), findsNothing);
    }
  });

  testWidgets('the US file offers neither section', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await openMarkets(tester, 'US');

    await openFilters(tester);
    expect(find.text('Sort by'), findsOneWidget, reason: 'the sheet is open');
    expect(find.text('Category'), findsNothing);
    expect(find.text('Issuer'), findsNothing);
  });

  testWidgets('the chips wrap rather than overflow at 320dp', (tester) async {
    // A layout overflow throws during the paint that follows it, so opening
    // the sheet at the narrowest size the app supports — with the longest
    // category label the pipeline publishes — is the whole assertion.
    await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
      size: const Size(512, 1024),
      devicePixelRatio: 1.6,
    );
    await openMarkets(tester, 'ASX');
    await openFilters(tester);

    expect(
      find.widgetWithText(FilterChip, 'Industrial Metals'),
      findsOneWidget,
    );
    // And it scrolls: the two new sections push the Apply button below the
    // fold on a short screen.
    await tester.dragFrom(const Offset(160, 500), const Offset(0, -300));
    await settle(tester, frames: 4);
    expect(find.text('Apply'), findsOneWidget);
  });

  testWidgets('a category filter does not survive the market switch', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await openMarkets(tester, 'ASX');

    await openFilters(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Crypto'));
    await settle(tester);
    await tester.tap(find.text('Apply'));
    await settle(tester);
    expect(find.text('GDX'), findsNothing);

    // The US file has no `category` column, so a filter left over from the
    // ASX list would silently mean nothing there — it is dropped instead.
    await openMarkets(tester, 'US');
    expect(find.text('MRNA'), findsWidgets);
    expect(
      tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
      isFalse,
      reason: 'the filter icon no longer claims a filter is on',
    );
  });
}
