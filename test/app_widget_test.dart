import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:screener/models/market.dart';
import 'package:screener/ui/screens/stock_detail_screen.dart';
import 'package:screener/ui/widgets/google_finance_button.dart';
import 'package:screener/ui/widgets/refresh_stamp.dart';
import 'package:screener/ui/widgets/stock_tile.dart';
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

  testWidgets('the dashboard shows one market and switches between them', (
    tester,
  ) async {
    await launch(tester);

    expect(find.text('Stocks Analysis'), findsOneWidget);

    // Every file is a segment on the context bar; one of them is on screen.
    for (final market in Market.values) {
      expect(
        find.descendant(
          of: find.byType(SegmentedButton<Market>),
          matching: find.text(market.label),
        ),
        findsOneWidget,
        reason: '${market.label} segment',
      );
    }

    // US is the default: its rows, not the ASX file's.
    expect(find.text('MRNA'), findsWidgets);
    expect(find.text('139.22'), findsWidgets);
    expect(find.text('QETH'), findsNothing);
    expect(find.textContaining('median 7D'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<Market>),
        matching: find.text('ASX'),
      ),
    );
    await settle(tester);
    expect(find.text('QETH'), findsWidgets);
    expect(find.text('MRNA'), findsNothing, reason: 'one file at a time');

    // Recent Analyses is built from the run metadata inside the file.
    expect(find.text('Recent Analyses'), findsOneWidget);
    expect(find.textContaining('7 Day Analysis'), findsWidgets);
  });

  testWidgets('the gainers are on the first screen beneath the controls', (
    tester,
  ) async {
    await launch(tester);

    // Three stacked market cards spent the whole first viewport on summaries.
    expect(
      tester.getTopLeft(find.text('Top Gainers (7 Day)')).dy,
      lessThan(300),
    );
  });

  testWidgets('the dashboard uses ranked, focused gainer tiles', (
    tester,
  ) async {
    await launch(tester);

    final tiles = find.byType(GainerTile);
    expect(tiles, findsWidgets);
    expect(tester.widget<GainerTile>(tiles.first).rank, 1);
    expect(tester.widget<GainerTile>(tiles.at(1)).rank, 2);

    // The whole row opens the stock detail page. A second external-link icon
    // made every compact row look like an action toolbar and is redundant here.
    expect(
      find.descendant(
        of: tiles.first,
        matching: find.byType(GoogleFinanceButton),
      ),
      findsNothing,
    );
  });

  testWidgets('the watchlist snapshot counts what the window leaves out', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'watchlist': ['us:MRNA', 'us:NVAX'],
    });
    await launch(tester);

    expect(find.text('Watchlist'), findsWidgets);
    // MRNA is in the 7-day window; NVAX is published only in the monthly one,
    // so the snapshot says so rather than quietly showing one of two.
    expect(find.textContaining('1 of 2 starred US stocks'), findsOneWidget);
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

  testWidgets('the quote leads with four tiles across the width', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    for (final label in [
      'Change',
      'Price Change',
      'First Price',
      'Last Price',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label tile missing');
    }

    // They run the width of the header. The two they replaced were pinned to
    // the right of a headline block that only needed its own width, so
    // everything between the two was a hole.
    final left = tester.getRect(find.text('Change').first).left;
    final right = tester.getRect(find.text('Last Price').first).right;
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(
      right - left,
      greaterThan(width * 0.75),
      reason: 'the tiles span the header rather than huddling on one side',
    );
  });

  testWidgets('the ticker, name and listing share one line', (tester) async {
    tester.view.physicalSize = const Size(640, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await launchApp(
      tester,
      cacheDir: tempDir,
      payloads: payloads,
      size: tester.view.physicalSize,
      devicePixelRatio: 1.0,
    );
    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    final detail = find.byType(StockDetailScreen);
    final ticker = tester.getRect(
      find.descendant(of: detail, matching: find.text('MRNA')).first,
    );
    final name = tester.getRect(
      find.descendant(
        of: detail,
        matching: find.text('Moderna, Inc. - Common Stock'),
      ),
    );

    // Stacked, these three lines pushed the price and its tiles down the
    // screen for nothing.
    expect(name.left, greaterThan(ticker.right));
    expect(name.center.dy, closeTo(ticker.center.dy, 4));
  });

  testWidgets('a wide quote puts the tiles beside the price', (tester) async {
    // 640dp: the handset shell, so the pushed detail is the whole window and
    // the width under test is the header's own. A threshold on the window's
    // width stacked the quote on panes far wider than this.
    tester.view.physicalSize = const Size(640, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await launchApp(
      tester,
      cacheDir: tempDir,
      payloads: payloads,
      size: tester.view.physicalSize,
      devicePixelRatio: 1.0,
    );
    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    final headline = tester.getRect(find.text('7 Day change, weekly closes'));
    final tile = tester.getRect(
      find.descendant(
        of: find.byType(StockDetailScreen),
        matching: find.text('Change'),
      ),
    );

    expect(
      tile.left,
      greaterThan(headline.right),
      reason: 'the tiles sit beside the headline, not under it',
    );
    expect(
      tile.top,
      lessThan(headline.top),
      reason: 'and on the price line rather than below the window it names',
    );
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

    await tester.tap(find.text('Performance'));
    await settle(tester);
    expect(find.text('Every window'), findsOneWidget);
  });

  testWidgets('the detail screen is three sections, links folded into the '
      'overview', (tester) async {
    await launch(tester);
    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    for (final tab in ['Overview', 'Performance', 'Metrics']) {
      expect(find.text(tab), findsOneWidget, reason: '$tab missing');
    }
    for (final gone in ['Windows', 'Links']) {
      expect(find.text(gone), findsNothing, reason: '$gone should be gone');
    }

    // What the Links tab carried is now the tail of the overview: where the
    // figures came from, and the link the pipeline published for them.
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await settle(tester);
    expect(find.text('Provenance'), findsOneWidget);
    expect(find.text('Market file'), findsOneWidget);
    expect(find.textContaining('Google Finance ·'), findsWidgets);
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

    await tester.tap(find.text('Watchlist').last);
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

  testWidgets('the dashboard dates the run, not the download', (tester) async {
    await launch(tester);

    // One stamp, for the market on screen.
    expect(find.byType(RefreshStamp), findsOneWidget);

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

  /// Wide enough for a row to have slack to strand, and still a handset. A
  /// loose Flexible is allocated a share of it and leaves what it does not use
  /// where it stands, so the trailing text floats inwards with the surplus
  /// behind it.
  Future<void> launchWide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await launchApp(
      tester,
      cacheDir: tempDir,
      payloads: payloads,
      size: tester.view.physicalSize,
      devicePixelRatio: 1.0,
    );
  }

  testWidgets('Recent Analyses stamps sit at the edge of their row', (
    tester,
  ) async {
    await launchWide(tester);

    final tile = find
        .ancestor(
          of: find.textContaining('7 Day Analysis').first,
          matching: find.byType(InkWell),
        )
        .first;
    final stamp = find.descendant(of: tile, matching: find.byType(Text)).last;
    expect(
      tester.getRect(tile).right - tester.getRect(stamp).right,
      closeTo(16, 1),
      reason: 'the stamp sits at the row padding, not adrift of it',
    );
  });

  testWidgets('a run id sits against the CSV button beside it', (tester) async {
    await launchWide(tester);

    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Runs and CSV export'), 200);
    await settle(tester, frames: 4);
    await tester.tap(find.text('Runs and CSV export'));
    await settle(tester);

    // The surplus a loose Flexible does not use is left at the end of the
    // row, past every child — so what it strands is the space after the
    // button, not the space before it.
    final button = find.byType(OutlinedButton).first;
    final row = find.ancestor(of: button, matching: find.byType(Padding)).first;
    expect(
      tester.getRect(row).right - tester.getRect(button).right,
      closeTo(12, 1),
      reason: 'the CSV button sits at the row padding, not adrift of it',
    );

    // And the run id is beside the button rather than swallowed.
    expect(
      find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('Z-')),
      findsWidgets,
    );
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
