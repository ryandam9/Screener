import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/market_database.dart';
import 'package:screener/models/market.dart';
import 'package:screener/ui/screens/history_screen.dart';
import 'package:screener/ui/widgets/google_finance_button.dart';
import 'package:screener/ui/widgets/price_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/fixture_database.dart';

/// The whole-market price history the ASX file publishes, and its page.
void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('screener_history');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<MarketDatabase> openFixture({
    List<FixtureHistoryBar> history = const [
      FixtureHistoryBar(ticker: 'AAA', date: '2026-08-07', close: 10),
      FixtureHistoryBar(ticker: 'AAA', date: '2026-08-14', close: 11),
      FixtureHistoryBar(ticker: 'AAA', date: '2026-08-21', close: 12.5),
      FixtureHistoryBar(ticker: 'BBB', date: '2026-08-07', close: 20),
      FixtureHistoryBar(ticker: 'BBB', date: '2026-08-21', close: 18),
    ],
    Map<String, String> tickerNames = const {},
  }) async {
    final path = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'asx.db',
      tablePrefix: 'asx_etf_growth',
      includeConsistentTable: false,
      history: history,
      tickerNames: tickerNames,
      weeklyBars: const [
        FixtureBar(date: '2026-08-14', ticker: 'AAA', close: 11),
        FixtureBar(date: '2026-08-21', ticker: 'AAA', close: 12.5),
      ],
      rowsBySuffix: const {
        '_7_days': [
          FixtureRow(
            ticker: 'AAA',
            name: 'Alpha ETF',
            exchange: 'ASX',
            assetType: 'etf',
            firstDate: '2026-08-14',
            firstPrice: 11,
            lastDate: '2026-08-21',
            latestPrice: 12.5,
            pctChange: 13.6,
          ),
        ],
      },
    );
    return MarketDatabase.open(Market.asx, path);
  }

  group('the data layer', () {
    test(
      'finds the history table without mistaking it for the series',
      () async {
        final db = await openFixture();
        addTearDown(db.close);

        expect(db.hasMarketHistory, isTrue);
        // The screener's own weekly series is a different table, and is still
        // found: both carry stock_price_date and close.
        expect(db.hasPriceHistory, isTrue);
        expect(db.availableWindows, isNotEmpty);
      },
    );

    test('summarises every ticker, strongest first', () async {
      final db = await openFixture();
      addTearDown(db.close);

      final tickers = await db.historyTickers();
      expect([for (final t in tickers) t.ticker], ['AAA', 'BBB']);

      final alpha = tickers.first;
      expect(alpha.bars, 3);
      expect(alpha.firstPrice, 10);
      expect(alpha.lastPrice, 12.5);
      expect(alpha.pctChange, closeTo(25, 0.001));
      expect(alpha.low, 10);
      expect(alpha.high, 12.5);
      expect(alpha.firstDate, DateTime(2026, 8, 7));
      expect(alpha.lastDate, DateTime(2026, 8, 21));

      // A faller keeps its sign rather than being dropped.
      expect(tickers.last.pctChange, closeTo(-10, 0.001));
    });

    test(
      'names come from the growth tables when there is no directory',
      () async {
        final db = await openFixture();
        addTearDown(db.close);

        final tickers = await db.historyTickers();
        expect(tickers.firstWhere((t) => t.ticker == 'AAA').name, 'Alpha ETF');
        // BBB never passed a screen, so the file has no name for it.
        expect(tickers.firstWhere((t) => t.ticker == 'BBB').name, isNull);
      },
    );

    test('asx_universe names every ticker, screened or not', () async {
      // The table the pipeline publishes alongside the history:
      //   SELECT u.name FROM ASX_1_YEAR_HISTORY h JOIN asx_universe u
      //   USING (ticker)
      final db = await openFixture(
        tickerNames: const {
          'AAA': 'Alpha Exchange Traded Fund',
          'BBB': 'Beta Bank Ltd',
          'CCC': 'Gamma Corp',
        },
      );
      addTearDown(db.close);

      final tickers = await db.historyTickers();
      expect(
        tickers.firstWhere((t) => t.ticker == 'BBB').name,
        'Beta Bank Ltd',
        reason: 'a ticker no screen ever picked up is named from the universe',
      );
      // The universe is the better source when both name a ticker: it carries
      // the whole market, and the growth tables only what they screened.
      expect(
        tickers.firstWhere((t) => t.ticker == 'AAA').name,
        'Alpha Exchange Traded Fund',
      );
      // A name for a ticker with no bars is simply unused.
      expect([for (final t in tickers) t.ticker], isNot(contains('CCC')));
    });

    test('the universe table is not mistaken for a screen result', () async {
      final db = await openFixture(tickerNames: const {'BBB': 'Beta Bank Ltd'});
      addTearDown(db.close);

      // Discovery has to tell four ticker-keyed tables apart in one file.
      expect(db.hasMarketHistory, isTrue);
      expect(db.hasPriceHistory, isTrue);
      expect(db.availableWindows, isNotEmpty);
      expect(db.hasRunMetadata, isFalse);
    });

    test('links to Google Finance over the year it charts', () async {
      final db = await openFixture(tickerNames: const {'BBB': 'Beta Bank Ltd'});
      addTearDown(db.close);

      final tickers = await db.historyTickers();
      final beta = tickers.firstWhere((t) => t.ticker == 'BBB');

      // The exchange comes from the universe table, and the window is the one
      // this page shows — the growth tables' own link points at five days.
      expect(beta.exchange, 'ASX');
      expect(
        beta.googleFinanceUrl,
        'https://www.google.com/finance/quote/BBB:ASX?window=1Y',
      );
    });

    test(
      'a ticker with no exchange gets no link rather than a broken one',
      () async {
        final db = await openFixture(
          history: const [
            FixtureHistoryBar(ticker: 'ZZZ', date: '2026-08-07', close: 5),
            FixtureHistoryBar(ticker: 'ZZZ', date: '2026-08-21', close: 6),
          ],
        );
        addTearDown(db.close);

        final zzz = (await db.historyTickers()).single;
        expect(zzz.exchange, isNull);
        expect(zzz.googleFinanceUrl, isNull);
      },
    );

    test('the bars of one ticker come back in order', () async {
      final db = await openFixture();
      addTearDown(db.close);

      final bars = await db.historyFor('AAA');
      expect(bars, hasLength(3));
      expect(bars.first.date.isBefore(bars.last.date), isTrue);
      expect(bars.last.plotPrice, 12.5);
      expect(await db.historyFor('NOPE'), isEmpty);
    });

    test('a file without the table says so rather than failing', () async {
      final db = await openFixture(history: const []);
      addTearDown(db.close);

      expect(db.hasMarketHistory, isFalse);
      expect(await db.historyTickers(), isEmpty);
      expect(await db.historyFor('AAA'), isEmpty);
    });
  });

  group('the page', () {
    late Directory cacheDir;
    late Directory serveDir;
    late Map<String, List<int>> payloads;

    /// The same pair, but with us.db publishing history of its own.
    late Map<String, List<int>> bothHistories;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cacheDir = await Directory.systemTemp.createTemp('screener_hist_cache');
      serveDir = await Directory.systemTemp.createTemp('screener_hist_serve');
      payloads = await buildFixturePayloads(serveDir);

      // Built here rather than in the test body: `testWidgets` runs in a
      // fake-async zone where real file I/O never completes.
      final usPath = await createFixtureDatabase(
        directory: serveDir,
        fileName: 'us_history.db',
        tablePrefix: 'us_stocks_growth',
        includeConsistentTable: false,
        history: const [
          FixtureHistoryBar(ticker: 'NVDA', date: '2026-08-07', close: 100),
          FixtureHistoryBar(ticker: 'NVDA', date: '2026-08-21', close: 140),
        ],
        historyTable: 'US_1_YEAR_HISTORY',
        tickerNames: const {'NVDA': 'NVIDIA Corporation'},
        universeTable: 'us_universe',
        rowsBySuffix: const {
          '_7_days': [
            FixtureRow(
              ticker: 'NVDA',
              name: 'NVIDIA Corporation',
              exchange: 'NASDAQ',
              firstDate: '2026-08-14',
              firstPrice: 120,
              lastDate: '2026-08-21',
              latestPrice: 140,
              pctChange: 16.7,
            ),
          ],
        },
      );
      bothHistories = {...payloads, 'us.db': await File(usPath).readAsBytes()};
    });

    tearDown(() async {
      for (final dir in [cacheDir, serveDir]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    testWidgets('lists every ticker, screened or not', (tester) async {
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        size: const Size(1440, 900),
        devicePixelRatio: 1.0,
      );

      await tester.tap(find.text('History'));
      await settle(tester);

      // QETH passed a screen and is named; ZZZQ never did and is listed all
      // the same, which is the point of the page.
      expect(find.text('QETH'), findsWidgets);
      expect(find.text('ZZZQ'), findsWidgets);
      expect(find.textContaining('3 tickers'), findsOneWidget);
    });

    testWidgets('stars a ticker no screen ever picked up', (tester) async {
      final prefs = await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        size: const Size(1440, 900),
        devicePixelRatio: 1.0,
      );

      await tester.tap(find.text('History'));
      await settle(tester);

      // ZZZQ is in no growth table, so this page is the only place it can be
      // starred from at all.
      final rows = tester.widgetList(find.text('ZZZQ')).length;
      await tester.tap(find.byTooltip('Add ZZZQ to watchlist'));
      await settle(tester);

      expect(prefs.getStringList('watchlist'), ['asx:ZZZQ']);
      expect(find.byTooltip('Remove ZZZQ from watchlist'), findsOneWidget);
      expect(
        find.text('ZZZQ'),
        findsNWidgets(rows),
        reason: 'the star must not also chart the row it sits in',
      );
    });

    testWidgets('starring one ticker leaves the others starred', (
      tester,
    ) async {
      final prefs = await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        size: const Size(1440, 900),
        devicePixelRatio: 1.0,
      );

      await tester.tap(find.text('History'));
      await settle(tester);

      await tester.tap(find.byTooltip('Add ZZZQ to watchlist'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add VBTC to watchlist'));
      await settle(tester);

      expect(prefs.getStringList('watchlist'), ['asx:VBTC', 'asx:ZZZQ']);
      expect(find.byTooltip('Remove ZZZQ from watchlist'), findsOneWidget);
      expect(find.byTooltip('Remove VBTC from watchlist'), findsOneWidget);
    });

    testWidgets('the chart page stars the ticker it is showing', (
      tester,
    ) async {
      final prefs = await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
      );

      await tester.tap(find.text('More'));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Price history'), 200);
      await settle(tester, frames: 4);
      await tester.tap(find.text('Price history'));
      await settle(tester);
      await tester.tap(find.text('QETH').first);
      await settle(tester);

      // The list is a route behind now, so this is the chart page's own star.
      await tester.tap(find.byTooltip('Add QETH to watchlist'));
      await settle(tester);

      expect(prefs.getStringList('watchlist'), ['asx:QETH']);
    });

    testWidgets('charts the ticker that is selected', (tester) async {
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        size: const Size(1440, 900),
        devicePixelRatio: 1.0,
      );

      await tester.tap(find.text('History'));
      await settle(tester);

      // The strongest ticker charts by default; picking another charts it.
      expect(find.byType(PriceChart), findsOneWidget);
      await tester.tap(find.text('ZZZQ').first);
      await settle(tester);

      expect(find.byType(PriceChart), findsOneWidget);
      expect(find.text('Published bars'), findsOneWidget);
    });

    testWidgets('the chart pane offers the Google Finance link', (
      tester,
    ) async {
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        size: const Size(1440, 900),
        devicePixelRatio: 1.0,
      );

      await tester.tap(find.text('History'));
      await settle(tester);

      // One per listed row, plus the one in the chart pane's header.
      final buttons = find.byType(GoogleFinanceButton);
      expect(buttons, findsWidgets);
      final urls = tester
          .widgetList<GoogleFinanceButton>(buttons)
          .map((button) => button.url)
          .toSet();
      expect(urls, everyElement(contains('window=1Y')));
      expect(
        urls,
        contains('https://www.google.com/finance/quote/QETH:ASX?window=1Y'),
      );
    });

    testWidgets('search narrows the list', (tester) async {
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        size: const Size(1440, 900),
        devicePixelRatio: 1.0,
      );

      await tester.tap(find.text('History'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).last, 'zzz');
      await settle(tester);

      expect(find.textContaining('1 of 3 tickers'), findsOneWidget);
      expect(find.text('QETH'), findsNothing);
    });

    testWidgets('a second market with history gets a switch', (tester) async {
      // Today only asx.db publishes the table. When us.db does too, the page
      // has to reach both rather than silently showing the first.
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: bothHistories,
        size: const Size(1440, 900),
        devicePixelRatio: 1.0,
      );

      await tester.tap(find.text('History'));
      await settle(tester);

      // The ASX comes first and charts by default; the US is one tap away.
      expect(find.text('QETH'), findsWidgets);
      await tester.tap(find.widgetWithText(InkWell, 'US').last);
      await settle(tester);

      expect(find.text('NVDA'), findsWidgets);
      expect(find.text('NVIDIA Corporation'), findsWidgets);
      expect(find.text('QETH'), findsNothing);
    });

    testWidgets('the handset pins the Google Finance link within reach', (
      tester,
    ) async {
      await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

      await tester.tap(find.text('More'));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Price history'), 200);
      await settle(tester, frames: 4);
      await tester.tap(find.text('Price history'));
      await settle(tester);
      await tester.tap(find.text('QETH').first);
      await settle(tester);

      // Full width and pinned to the bottom of the window, not somewhere in
      // the scroll: a thumb has to reach it without reading the page first.
      final action = find.widgetWithText(
        FilledButton,
        'QETH on Google Finance',
      );
      expect(action, findsOneWidget);

      final box = tester.getRect(action);
      final window = tester.getRect(find.byType(Scaffold).last);
      expect(box.width, greaterThan(window.width * 0.8));
      expect(
        window.bottom - box.bottom,
        lessThan(window.height * 0.12),
        reason: 'the button should sit in the bottom tenth of the window',
      );

      // And it is the only copy on the page — the pane's own footer is off.
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('a handset opens the chart as its own page', (tester) async {
      await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

      await tester.tap(find.text('More'));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Price history'), 200);
      await settle(tester, frames: 4);
      await tester.tap(find.text('Price history'));
      await settle(tester);

      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.byType(PriceChart), findsNothing, reason: 'list first');

      await tester.tap(find.text('QETH').first);
      await settle(tester);
      expect(find.byType(PriceChart), findsOneWidget);
    });
  });
}
