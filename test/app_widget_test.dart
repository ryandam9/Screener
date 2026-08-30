import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:screener/models/market.dart';
import 'package:screener/ui/screens/stock_detail_screen.dart';
import 'package:screener/ui/widgets/change_chip.dart';
import 'package:screener/ui/widgets/refresh_stamp.dart';
import 'package:screener/ui/widgets/stock_tile.dart';
import 'package:screener/ui/widgets/watchlist_star.dart';
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

    // The headline follows the weekly closes the chart draws: the fixture's
    // bars run 57.10 -> 139.225, which is +143.83%, not the screener's
    // +472.50% measured from its own calendar start.
    expect(find.textContaining('+143.83%'), findsWidgets);
    expect(find.text('1 Year change, weekly closes'), findsOneWidget);
    // The published figure stays on screen rather than being replaced.
    expect(find.text('screener: +472.50%'), findsOneWidget);

    await tester.tap(find.text('Metrics'));
    await settle(tester);
    expect(find.text('Key Metrics'), findsOneWidget);
    expect(find.text('Detailed Metrics'), findsOneWidget);

    // Both sources are listed, each attributed.
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await settle(tester);
    expect(find.text('Screener change'), findsOneWidget);
    expect(find.text('Weekly change'), findsOneWidget);

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

  testWidgets('most traded names what they did, and labels the column once', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.text('Analysis'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Most traded'), 200);
    await settle(tester);

    // The caption sits over the column, not under every number in it.
    expect(find.text('median volume'), findsOneWidget);

    // Volume is why a row is in this list; the move is why the file exists,
    // and the panel used to leave it out entirely.
    expect(
      find.descendant(
        of: find.byType(StockTile),
        matching: find.byType(ChangeChip),
      ),
      findsWidgets,
      reason: 'a most-traded row says what the ticker did',
    );
  });

  testWidgets('most traded rows sit in the same columns as every other list', (
    tester,
  ) async {
    // At a phone width, where the row has the least room to waste.
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await launchApp(
      tester,
      cacheDir: tempDir,
      payloads: payloads,
      size: tester.view.physicalSize,
      devicePixelRatio: 1.0,
    );

    /// How far the change chip's right edge sits from the row's own.
    /// Measured rather than asserted in pixels: the test font is far wider
    /// than Inter, so the only stable check is one row against another.
    double chipInset(Finder tile) {
      final chip = find.descendant(of: tile, matching: find.byType(ChangeChip));
      return tester.getBottomRight(tile).dx - tester.getBottomRight(chip).dx;
    }

    await tester.tap(find.text('Analysis'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Most traded'), 200);
    await settle(tester);

    // The only tiles on this screen are the most-traded rows.
    final traded = find.byType(StockTile).first;
    final tradedInset = chipInset(traded);

    final starY = tester
        .getCenter(
          find.descendant(of: traded, matching: find.byType(WatchlistStar)),
        )
        .dy;
    final chipY = tester
        .getCenter(
          find.descendant(of: traded, matching: find.byType(ChangeChip)),
        )
        .dy;

    await tester.tap(find.text('Markets').last);
    await settle(tester);

    // The trailing slot used to be a loose Flexible, which claims a share of
    // the row's free space and leaves whatever it does not use as a hole
    // after the last icon.
    expect(
      tradedInset,
      closeTo(chipInset(find.byType(StockTile).first), 0.5),
      reason: 'the chip ends where it does in the market list',
    );

    // One line, so the star sits level with the numbers beside it rather than
    // floating between two stacked ones.
    expect(starY, closeTo(chipY, 1));
  });

  testWidgets('the dashboard dates the run, not the download', (tester) async {
    await launch(tester);

    // One stamp per market card, because the two runs are independent.
    expect(find.byType(RefreshStamp), findsNWidgets(Market.values.length));

    // The fixture's run is stamped 22 August 2026 UTC; the download happened
    // in this test, seconds ago. A label saying "Today" would be dating the
    // download — the thing the reader cannot use.
    expect(find.textContaining('Refreshed'), findsWidgets);
    expect(find.textContaining('Refreshed Today'), findsNothing);

    // And the run's date is the one in the tooltip.
    final tooltip = tester
        .widgetList<Tooltip>(
          find.descendant(
            of: find.byType(RefreshStamp).first,
            matching: find.byType(Tooltip),
          ),
        )
        .first;
    // Read back in the host's zone, which is where the stamp is rendered: the
    // run id is UTC, and east of Greenwich it lands on the following day.
    final runDay = DateFormat(
      'MMM d, yyyy',
    ).format(DateTime.utc(2026, 8, 22, 22, 44, 30).toLocal());
    expect(tooltip.message, contains('Run finished $runDay'));
  });

  testWidgets('the tooltip separates the run from the download', (
    tester,
  ) async {
    await launch(tester);

    final stamp = tester.widgetList<Tooltip>(
      find.descendant(
        of: find.byType(RefreshStamp).first,
        matching: find.byType(Tooltip),
      ),
    );
    final message = stamp.first.message!;
    expect(message, contains('Prices as of'));
    expect(message, contains('Run finished'));
    expect(message, contains('Downloaded to this device'));
  });

  testWidgets('a cached file says so rather than claiming to be current', (
    tester,
  ) async {
    var failing = false;
    await launch(tester, shouldFail: () => failing);
    expect(find.textContaining('Refreshed'), findsWidgets);

    // Take the server away and ask for a re-download: the rows stay, and the
    // stamp stops claiming they are today's.
    failing = true;
    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Re-download'));
    // Longer than the default: this is every published file being fetched in
    // turn, and the assertions below are about what the stamps say once all
    // of them are done.
    await settle(tester, frames: 60);
    await tester.tap(find.text('Dashboard'));
    await settle(tester);

    expect(find.textContaining('Cached'), findsWidgets);
    expect(find.textContaining('Refreshed'), findsNothing);
  });

  testWidgets('Reports stacks the run panels on a handset', (tester) async {
    await launch(tester);

    await tester.tap(find.text('More'));
    await settle(tester);
    // Below the fold on a handset, under the data-source and digest sections.
    await tester.scrollUntilVisible(find.text('Runs and CSV export'), 200);
    await settle(tester, frames: 4);
    await tester.tap(find.text('Runs and CSV export'));
    await settle(tester);

    // The ASX fixture publishes both tables; at handset width they stack
    // rather than sitting side by side.
    expect(find.text('Run metadata'), findsOneWidget);
    expect(find.text('Screen funnel'), findsOneWidget);
    expect(find.text('Universe in window'), findsOneWidget);
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
    // Longer than the default: this is every published file being fetched in
    // turn, and the assertions below are about what the stamps say once all
    // of them are done.
    await settle(tester, frames: 60);

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
