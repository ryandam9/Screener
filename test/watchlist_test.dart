import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/models/market.dart';
import 'package:screener/theme/app_theme.dart';
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

  /// Switches the dashboard's context bar to [market].
  ///
  /// Scrolls back to the top first: starring a row scrolls the list, and the
  /// context bar is the first thing on it.
  Future<void> selectMarket(WidgetTester tester, String market) async {
    await tester.drag(find.byType(GainerTile).first, const Offset(0, 1200));
    await settle(tester, frames: 6);
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<Market>),
        matching: find.text(market),
      ),
    );
    await settle(tester);
  }

  /// The star inside the dashboard's Top Gainers row for [ticker].
  ///
  /// `.first` because a starred ticker shows up twice on the dashboard: in the
  /// gainers list and again in the watchlist snapshot below it.
  Finder starFor(String ticker) => find
      .descendant(
        of: find.ancestor(
          of: find.text(ticker),
          matching: find.byType(GainerTile),
        ),
        matching: find.byType(WatchlistStar),
      )
      .first;

  /// Stars [ticker] from its dashboard row, scrolling to it first.
  ///
  /// A tap that lands outside the viewport does nothing at all rather than
  /// failing, so the row is brought on screen first.
  Future<void> tapStar(WidgetTester tester, String ticker) async {
    await tester.ensureVisible(starFor(ticker));
    await settle(tester, frames: 4);
    await tester.tap(starFor(ticker));
    await settle(tester);
  }

  /// The colour painted behind the row that lists [ticker].
  ///
  /// A row that grows into the detail screen paints its background as the
  /// closed colour of its `OpenContainer`; the rest are plain Materials.
  Color? rowColour(WidgetTester tester, String ticker) {
    final text = find.text(ticker).first;
    final container = find.ancestor(
      of: text,
      matching: find.byType(OpenContainer<void>),
    );
    if (container.evaluate().isNotEmpty) {
      return tester.widget<OpenContainer<void>>(container.first).closedColor;
    }
    final material = find.ancestor(of: text, matching: find.byType(Material));
    return tester.widget<Material>(material.first).color;
  }

  /// The tint a starred row carries, in whichever theme is showing.
  Color starredSurface(WidgetTester tester) => Theme.of(
    tester.element(find.byType(GainerTile).first),
  ).extension<ScreenerColors>()!.starredSurface;

  /// Opens the market list on [market], via the sheet behind the title.
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
    if (find.byType(SegmentedButton<Market>).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
    }
  }

  /// Switches the market list to the window named [longLabel].
  Future<void> selectWindow(WidgetTester tester, String longLabel) async {
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await settle(tester);
    await tester.tap(find.text('$longLabel analysis'));
    await settle(tester);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text(label)),
    );
    await settle(tester);
  }

  testWidgets('a list row stars without opening the row', (tester) async {
    final prefs = await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
    );

    await tapStar(tester, 'MRNA');

    expect(
      find.byType(StockDetailScreen),
      findsNothing,
      reason: 'the star must not also open the row',
    );
    expect(prefs.getStringList('watchlist'), ['us:MRNA']);
  });

  testWidgets('a star from a list row reaches the watchlist', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    await tapStar(tester, 'MRNA');

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

    await tapStar(tester, 'MRNA');
    expect(prefs.getStringList('watchlist'), ['us:MRNA']);

    await tapStar(tester, 'MRNA');
    expect(prefs.getStringList('watchlist'), isEmpty);
  });

  testWidgets('the star survives a restart', (tester) async {
    final prefs = await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
    );
    await tapStar(tester, 'MRNA');

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

    await tapStar(tester, 'MRNA');
    await selectMarket(tester, 'ASX');
    await tapStar(tester, 'QETH');

    expect(prefs.getStringList('watchlist'), ['asx:QETH', 'us:MRNA']);
  });

  testWidgets('a starred ticker is marked in every list it shows up in', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    // Nothing is starred yet, so the two dashboard rows look alike.
    expect(rowColour(tester, 'MRNA'), rowColour(tester, 'AMLX'));

    await tapStar(tester, 'MRNA');
    final tint = starredSurface(tester);

    expect(
      rowColour(tester, 'MRNA'),
      tint,
      reason: 'the row it was starred from',
    );
    expect(
      rowColour(tester, 'AMLX'),
      isNot(tint),
      reason: 'only the starred ticker is marked',
    );

    // The 7-day US list: a different screen, built from a different query,
    // which was never told about the star.
    await openMarkets(tester, 'US');
    expect(rowColour(tester, 'MRNA'), tint, reason: '7 day list');
    expect(rowColour(tester, 'AMLX'), isNot(tint), reason: '7 day list');

    // And the monthly one, where MRNA is the only fixture row.
    await selectWindow(tester, '1 Month');
    expect(rowColour(tester, 'MRNA'), tint, reason: '1 month list');
  });

  testWidgets('the consistent growers list stars and marks a ticker', (
    tester,
  ) async {
    final prefs = await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
    );
    final tint = starredSurface(tester);

    await openMarkets(tester, 'US');
    await openTab(tester, 'Consistent');
    expect(
      find.text('MRNA'),
      findsWidgets,
      reason: 'the fixture consistent row',
    );
    expect(rowColour(tester, 'MRNA'), isNot(tint));

    // Starrable from here too, not only from the windowed lists.
    await tester.tap(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(WatchlistStar),
          )
          .first,
    );
    await settle(tester);

    expect(prefs.getStringList('watchlist'), ['us:MRNA']);
    expect(rowColour(tester, 'MRNA'), tint);
  });

  testWidgets('the price history page marks a starred ticker', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await selectMarket(tester, 'ASX');
    await tapStar(tester, 'QETH');
    final tint = starredSurface(tester);

    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Price history'), 200);
    await settle(tester, frames: 4);
    await tester.tap(find.text('Price history'));
    await settle(tester);

    expect(rowColour(tester, 'QETH'), tint);
    expect(rowColour(tester, 'VBTC'), isNot(tint));
  });

  testWidgets('the watchlist keeps every starred ticker, whatever the run '
      'still lists', (tester) async {
    // Three shapes at once: MRNA is in the selected 7-day window, NVAX is
    // published only in the monthly one, and ZZZZ is in no table at all.
    SharedPreferences.setMockInitialValues({
      'watchlist': ['us:MRNA', 'us:NVAX', 'us:ZZZZ'],
    });
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    await tester.tap(find.text('Watchlist').last);
    await settle(tester);

    expect(find.text('MRNA'), findsWidgets, reason: 'in the 7 day window');
    expect(find.text('NVAX'), findsWidgets, reason: 'only in the 1 month one');
    expect(find.text('ZZZZ'), findsWidgets, reason: 'dropped from the run');

    expect(
      find.text('Not in the 7 day screen — showing its 1 month row'),
      findsOneWidget,
      reason: 'a borrowed row says which window it came from',
    );
    expect(find.text('Dropped from the latest run'), findsOneWidget);
    expect(
      find.textContaining('1 of 3 starred tickers'),
      findsOneWidget,
      reason: 'the header counts what the selected window covers',
    );
  });

  testWidgets('swiping a starred ticker away can be undone', (tester) async {
    SharedPreferences.setMockInitialValues({
      'watchlist': ['us:MRNA', 'us:NVAX'],
    });
    final prefs = await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
    );

    await tester.tap(find.text('Watchlist').last);
    await settle(tester);

    await tester.drag(find.text('NVAX').first, const Offset(-500, 0));
    await settle(tester);
    expect(prefs.getStringList('watchlist'), ['us:MRNA']);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(prefs.getStringList('watchlist'), ['us:MRNA', 'us:NVAX']);
  });

  testWidgets('clearing the watchlist from settings asks first', (
    tester,
  ) async {
    final prefs = await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
    );
    await tapStar(tester, 'MRNA');

    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Starred tickers'), 200);
    await settle(tester, frames: 4);

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await settle(tester);
    expect(find.text('Clear watchlist?'), findsOneWidget);

    // Backing out leaves the star where it was: a star stays until it is
    // taken off deliberately.
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(prefs.getStringList('watchlist'), ['us:MRNA']);

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await settle(tester);
    expect(prefs.getStringList('watchlist'), isEmpty);
  });
}
