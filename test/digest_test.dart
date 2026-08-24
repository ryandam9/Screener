import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/db_sync_service.dart';
import 'package:screener/models/daily_digest.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/models/market.dart';
import 'package:screener/models/stock_row.dart';
import 'package:screener/services/digest_scheduler.dart';
import 'package:screener/services/digest_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:screener/state/digest_router.dart';
import 'package:screener/ui/screens/market_list_screen.dart';

import 'support/app_harness.dart';

/// The morning digest of the 7-day screen: what it says, and when it says it.
void main() {
  StockRow row(
    String ticker,
    double pctChange, {
    Market market = Market.us,
    String? name,
  }) => StockRow(
    market: market,
    window: GrowthWindow.sevenDays,
    ticker: ticker,
    name: name ?? '$ticker Inc.',
    exchange: market == Market.us ? 'NASDAQ' : 'ASX',
    assetType: 'common_stock',
    firstDate: '2026-08-14',
    firstPrice: 100,
    lastDate: '2026-08-21',
    latestPrice: 100 + pctChange,
    pctChange: pctChange,
    threshold: 10,
    observations: 6,
    daysCovered: 7,
    coverage: 1,
    observationRatio: 1,
    medianVolume: 1000,
    priceBasis: 'adjusted',
    dataAsOf: '2026-08-21',
    runId: 'r1',
    googleFinanceUrl: null,
  );

  final today = DateTime(2026, 8, 24, 8, 15);

  group('the digest itself', () {
    test('the first run has no newcomers to claim', () {
      final digest = DailyDigest.build(
        rows: [row('MRNA', 117.9), row('AMLX', 81.9)],
        previousKeys: const {},
        date: today,
      );

      expect(digest.isFirstRun, isTrue);
      expect(digest.newKeys, isEmpty);
      expect(digest.title, '2 in the 7-day screen');
      expect(digest.body, contains('MRNA +117.9%'));
    });

    test('names what is new since the last run, strongest first', () {
      final digest = DailyDigest.build(
        rows: [row('AMLX', 81.9), row('VOGX', 74.2), row('MRNA', 117.9)],
        previousKeys: const {'us:MRNA'},
        date: today,
      );

      expect(digest.title, '2 new in the 7-day screen');
      expect([for (final r in digest.newcomers) r.ticker], ['AMLX', 'VOGX']);
      // The body leads with the newcomers, not with the strongest row, which
      // was already in yesterday's digest.
      expect(digest.body, startsWith('AMLX +81.9%, VOGX +74.2%'));
      expect(digest.body, isNot(contains('MRNA')));
    });

    test('reports the tickers the run dropped', () {
      final digest = DailyDigest.build(
        rows: [row('MRNA', 117.9)],
        previousKeys: const {'us:MRNA', 'us:AMLX'},
        date: today,
      );

      expect(digest.droppedKeys, {'us:AMLX'});
      expect(digest.newKeys, isEmpty);
    });

    test('a quiet day still says what is in the screen', () {
      final digest = DailyDigest.build(
        rows: [row('MRNA', 117.9)],
        previousKeys: const {'us:MRNA'},
        date: today,
      );

      expect(digest.title, '1 in the 7-day screen');
      expect(digest.body, contains('no new names since the last run'));
    });

    test('caps the names and counts the rest', () {
      final digest = DailyDigest.build(
        rows: [
          for (var i = 0; i < 7; i++) row('T$i', 50 - i.toDouble()),
        ],
        previousKeys: const {'us:GONE'},
        date: today,
      );

      expect(digest.title, '7 new in the 7-day screen');
      expect(digest.body, contains('and 3 more'));
    });

    test('counts each market separately', () {
      final digest = DailyDigest.build(
        rows: [
          row('MRNA', 117.9),
          row('QETH', 21.0, market: Market.asx),
          row('VBTC', 14.4, market: Market.asx),
        ],
        previousKeys: const {},
        date: today,
      );

      expect(digest.countFor(Market.asx), 2);
      expect(digest.countFor(Market.us), 1);
      expect(digest.body, contains('2 ASX'));
      expect(digest.body, contains('1 US'));
    });

    test('an empty run says so rather than pretending', () {
      final digest = DailyDigest.build(
        rows: const [],
        previousKeys: const {'us:MRNA'},
        date: today,
      );

      expect(digest.isEmpty, isTrue);
      expect(digest.title, 'No 7-day screen published today');
    });
  });

  group('sending it', () {
    late Directory cacheDir;
    late Directory serveDir;
    late Map<String, List<int>> payloads;
    late SharedPreferences prefs;
    late FakeNotifier notifier;
    late DbSyncService sync;
    late DateTime now;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      cacheDir = await Directory.systemTemp.createTemp('screener_digest_cache');
      serveDir = await Directory.systemTemp.createTemp('screener_digest_serve');
      payloads = await buildFixturePayloads(serveDir);
      notifier = FakeNotifier();
      now = DateTime(2026, 8, 24, 8, 15);
      sync = fixtureSyncService(
        preferences: prefs,
        cacheDir: cacheDir,
        payloads: payloads,
      );
    });

    tearDown(() async {
      sync.dispose();
      for (final dir in [cacheDir, serveDir]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    DigestService service() => DigestService(
      preferences: prefs,
      sync: sync,
      notifier: notifier,
      clock: () => now,
    );

    test('posts the digest, then leaves the day alone', () async {
      final digest = service();

      final first = await digest.run();
      expect(first, isNotNull);
      expect(notifier.posted, hasLength(1));
      expect(notifier.last!.title, contains('7-day screen'));
      expect(notifier.last!.payload, DigestService.tapPayload);
      // The fixture publishes MRNA and AMLX for the US, QETH for the ASX.
      expect(notifier.last!.body, contains('MRNA'));

      // Opening the app again the same day must not post a second time.
      expect(await digest.run(), isNull);
      expect(notifier.posted, hasLength(1));
    });

    test('the snapshot makes tomorrow a comparison', () async {
      await service().run();
      expect(service().snapshot, contains('us:MRNA'));

      now = now.add(const Duration(days: 1));
      final second = await service().run();

      expect(second, isNotNull);
      expect(second!.isFirstRun, isFalse);
      expect(
        second.newKeys,
        isEmpty,
        reason: 'the fixture publishes the same rows both days',
      );
      expect(notifier.posted, hasLength(2));
      expect(notifier.posted.last.body, contains('no new names'));
    });

    test('a forced send ignores the once-a-day guard', () async {
      final digest = service();
      await digest.run();
      expect(await digest.run(force: true), isNotNull);
      expect(notifier.posted, hasLength(2));
    });

    test('a failed download still summarises the cache', () async {
      // Prime the cache, then take the server away.
      await service().run();
      final offline = DigestService(
        preferences: prefs,
        sync: fixtureSyncService(
          preferences: prefs,
          cacheDir: cacheDir,
          payloads: payloads,
          shouldFail: () => true,
        ),
        notifier: notifier,
        clock: () => now.add(const Duration(days: 1)),
      );

      final digest = await offline.run();
      expect(digest, isNotNull);
      expect(digest!.isEmpty, isFalse);
    });

    test('nothing cached means nothing posted', () async {
      final empty = await Directory.systemTemp.createTemp('screener_no_cache');
      addTearDown(() => empty.delete(recursive: true));

      final offline = DigestService(
        preferences: prefs,
        sync: fixtureSyncService(
          preferences: prefs,
          cacheDir: empty,
          payloads: payloads,
          shouldFail: () => true,
        ),
        notifier: notifier,
        clock: () => now,
      );

      final digest = await offline.run();
      expect(digest!.isEmpty, isTrue);
      expect(notifier.posted, isEmpty, reason: 'an empty digest is not news');
      expect(
        prefs.getString('digest_last_sent'),
        isNull,
        reason: 'the day is not spent on a digest that never went out',
      );
    });
  });

  group('on screen', () {
    late Directory cacheDir;
    late Directory serveDir;
    late Map<String, List<int>> payloads;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cacheDir = await Directory.systemTemp.createTemp('screener_dui_cache');
      serveDir = await Directory.systemTemp.createTemp('screener_dui_serve');
      payloads = await buildFixturePayloads(serveDir);
    });

    tearDown(() async {
      for (final dir in [cacheDir, serveDir]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    Future<void> openSettings(WidgetTester tester, FakeNotifier notifier) async {
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        notifier: notifier,
      );
      await tester.tap(find.text('More'));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Morning digest'), 200);
      await settle(tester, frames: 4);
    }

    testWidgets('turning it on asks for permission and remembers', (
      tester,
    ) async {
      final notifier = FakeNotifier();
      await openSettings(tester, notifier);

      final toggle = find.ancestor(
        of: find.text('Morning digest'),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(find.descendant(of: toggle, matching: find.byType(Switch)));
      await settle(tester);

      expect(notifier.permissionRequests, 1);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('digest_enabled'), isTrue);
    });

    testWidgets('a refusal leaves it off and says why', (tester) async {
      final notifier = FakeNotifier(permitted: false);
      await openSettings(tester, notifier);

      final toggle = find.ancestor(
        of: find.text('Morning digest'),
        matching: find.byType(SwitchListTile),
      );
      await tester.tap(find.descendant(of: toggle, matching: find.byType(Switch)));
      await settle(tester);

      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(find.textContaining('blocked'), findsOneWidget);
    });

    testWidgets('"Send one now" posts today’s digest', (tester) async {
      final notifier = FakeNotifier();
      await openSettings(tester, notifier);

      await tester.tap(find.text('Send one now'));
      await settle(tester);

      expect(notifier.posted, hasLength(1));
      expect(notifier.last!.body, contains('MRNA'));
    });

    testWidgets('tapping the digest lands on the 7-day list', (tester) async {
      final router = DigestRouter()..requestSevenDayList();
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        router: router,
      );
      await settle(tester);

      expect(find.byType(MarketListScreen), findsOneWidget);
      expect(router.showSevenDayList, isFalse, reason: 'the request is spent');
    });
  });

  group('when it goes out', () {
    test('waits for today’s time, or tomorrow’s if it has passed', () {
      const at = TimeOfDay(hour: 8, minute: 15);

      expect(
        DigestScheduler.delayUntil(at, DateTime(2026, 8, 24, 6, 15)),
        const Duration(hours: 2),
      );
      expect(
        DigestScheduler.delayUntil(at, DateTime(2026, 8, 24, 9, 15)),
        const Duration(hours: 23),
      );
      // Exactly on the minute counts as passed: a zero delay would fire the
      // moment the setting is saved.
      expect(
        DigestScheduler.delayUntil(at, DateTime(2026, 8, 24, 8, 15)),
        const Duration(hours: 24),
      );
    });
  });
}
