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
import 'package:screener/services/notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:provider/provider.dart';
import 'package:screener/state/app_state.dart';
import 'package:screener/state/digest_router.dart';
import 'package:screener/ui/desktop/desktop_shell.dart';
import 'package:screener/ui/screens/home_shell.dart';
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

    test('the alert budget is shared out, not taken by the loudest file', () {
      // What production looks like: hundreds of US rows moving in the
      // hundreds of percent, a couple of ASX rows in the twenties.
      final digest = DailyDigest.build(
        rows: [
          for (var i = 0; i < 20; i++) row('US$i', 400 - i.toDouble()),
          row('QETH', 21.0, market: Market.asx),
          row('VBTC', 14.4, market: Market.asx),
        ],
        previousKeys: const {'us:GONE'},
        date: today,
      );

      final alerts = digest.alerts(budget: 8);
      expect(alerts, hasLength(8));
      expect(
        [for (final r in alerts) r.ticker],
        containsAll(['QETH', 'VBTC']),
        reason: 'no ASX row ever out-moves a US one, so a strongest-first '
            'cap would never announce one',
      );
      // The rest of the budget still goes to the strongest, in order.
      expect(alerts.first.ticker, 'US0');
      expect([for (final r in alerts) r.ticker].take(3), ['US0', 'US1', 'US2']);
    });

    test('a file with nothing new leaves its share to the other', () {
      final digest = DailyDigest.build(
        rows: [for (var i = 0; i < 10; i++) row('US$i', 100 - i.toDouble())],
        previousKeys: const {'us:GONE'},
        date: today,
      );

      expect(digest.alerts(budget: 4), hasLength(4));
      expect(digest.newcomersFor(Market.asx), isEmpty);
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

  group('sending alerts', () {
    late Directory cacheDir;
    late Directory serveDir;
    late Map<String, List<int>> payloads;
    late SharedPreferences prefs;
    late FakeNotifier notifier;
    late DbSyncService sync;
    late DateTime now;
    late String version;

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
      now = DateTime(2026, 8, 24, 9, 0);
      version = '1';
      sync = fixtureSyncService(
        preferences: prefs,
        cacheDir: cacheDir,
        payloads: payloads,
        version: () => version,
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

    test('the first run takes a baseline without announcing it', () async {
      final digest = (await service().run()).digest!;

      expect(digest.isFirstRun, isTrue);
      expect(
        notifier.posted,
        isEmpty,
        reason: 'a first run has no yesterday to call anything new against',
      );
      expect(service().snapshot, contains('us:MRNA'));
    });

    test('a ticker that joins the screen gets its own alert', () async {
      // Yesterday saw everything except AMLX.
      await prefs.setStringList('digest_snapshot_7d', [
        'us:MRNA',
        'asx:QETH',
      ]);

      final digest = (await service().run()).digest!;
      expect(digest.newKeys, {'us:AMLX'});

      expect(notifier.posted, hasLength(1), reason: 'one ticker, one alert');
      final alert = notifier.last!;
      // The name is the point of the alert, so it is in the title rather than
      // buried in a body the shade may collapse.
      expect(alert.title, 'AMLX — Amylyx Pharmaceuticals, Inc.');
      expect(alert.body, startsWith('Increased 81.9% in the last week.'));
      expect(alert.body, contains(r'Current price $39.16'));
      expect(alert.body, contains('cut-off 10%'));
      expect(alert.payload, DigestService.tapPayload);
      expect(alert.group, NotificationIds.sevenDayGroup);
      expect(alert.isGroupSummary, isFalse);
    });

    test('several newcomers are grouped under a summary', () async {
      await prefs.setStringList('digest_snapshot_7d', ['us:GONE']);

      await service().run();

      final summaries = notifier.posted.where((n) => n.isGroupSummary);
      expect(summaries, hasLength(1));
      expect(summaries.single.title, contains('new in the 7-day screen'));
      // One per ticker, plus the summary above them.
      expect(notifier.posted.length, greaterThan(2));
      expect(
        notifier.posted.where((n) => !n.isGroupSummary).map((n) => n.title),
        contains('MRNA — Moderna, Inc.'),
      );

      // The summary is a list, not a paragraph: one line per ticker, which is
      // what Android expands the collapsed group into.
      final summary = summaries.single;
      expect(
        summary.lines,
        hasLength(notifier.posted.length - 1),
        reason: 'a line for each ticker posted under it',
      );
      expect(summary.lines.first, startsWith('MRNA +117.9%'));
      expect(summary.lines.first, contains('Moderna, Inc.'));
      expect(summary.summaryText, contains('US'));
    });

    test('an ASX newcomer is alerted even when US moves harder', () async {
      // Both files carry newcomers; the US ones are larger, and under a
      // strongest-first cap they would take every slot.
      await prefs.setStringList('digest_snapshot_7d', ['us:GONE']);

      await service().run();

      final titles = notifier.posted
          .where((n) => !n.isGroupSummary)
          .map((n) => n.title)
          .toList();
      expect(
        titles.where((title) => title.startsWith('QETH')),
        isNotEmpty,
        reason: 'the ASX file is watched for a reason',
      );
    });

    test('nothing new means nothing posted, however often it runs', () async {
      await service().run();
      notifier.posted.clear();

      await service().run();
      await service().run();
      expect(notifier.posted, isEmpty);
    });

    test('an alert is not repeated the next day', () async {
      await prefs.setStringList('digest_snapshot_7d', ['us:MRNA']);
      await service().run();
      expect(notifier.posted, isNotEmpty);

      notifier.posted.clear();
      now = now.add(const Duration(days: 1));
      await service().run();
      expect(notifier.posted, isEmpty);
    });

    test('a forced check posts even when nothing is new', () async {
      await service().run();
      notifier.posted.clear();

      await service().run(force: true);
      expect(notifier.posted, isNotEmpty);
    });

    test('a run that adds many tickers caps the alerts', () {
      // The cap is on the alerts, not on the digest, which still counts them.
      expect(DigestService.maxAlerts, lessThan(20));
    });

    test('an alert prices each market in its own currency', () {
      final asx = DigestService.alertBody(
        row('QETH', 21.0, market: Market.asx),
      );
      expect(asx, startsWith('Increased 21.0% in the last week.'));
      expect(asx, contains(r'Current price A$121.00'));

      final us = DigestService.alertBody(row('MRNA', 117.9));
      expect(us, contains(r'Current price $217.90'));
      expect(us, isNot(contains(r'A$')));
    });

    test('a refreshed file is announced once, when it changes', () async {
      // The first sync has nothing to compare against, so it is recorded.
      expect(await service().refresh(), isEmpty);
      expect(notifier.posted, isEmpty);

      // Unchanged bytes: the conditional request says nothing happened.
      expect(await service().refresh(), isEmpty);
      expect(notifier.posted, isEmpty);

      // A new publish changes the ETag.
      version = '2';
      final changed = await service().refresh();
      expect(changed, hasLength(2), reason: 'both files were republished');
      expect(notifier.posted, hasLength(2));
      expect(
        notifier.posted.map((n) => n.title),
        containsAll(['asx.db refreshed', 'us.db refreshed']),
      );
      expect(notifier.posted.first.body, contains('downloaded'));
    });

    test('a failed download is not announced', () async {
      final offline = DigestService(
        preferences: prefs,
        sync: fixtureSyncService(
          preferences: prefs,
          cacheDir: cacheDir,
          payloads: payloads,
          shouldFail: () => true,
        ),
        notifier: notifier,
        clock: () => now,
      );

      expect(await offline.refresh(), isEmpty);
      expect(notifier.posted, isEmpty);
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

      final digest = (await offline.run()).digest!;
      expect(digest.isEmpty, isTrue);
      expect(notifier.posted, isEmpty, reason: 'an empty screen is not news');
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
      await tester.scrollUntilVisible(find.text('Refresh and alerts'), 200);
      await settle(tester, frames: 4);
    }

    testWidgets('turning it on asks for permission and remembers', (
      tester,
    ) async {
      final notifier = FakeNotifier();
      await openSettings(tester, notifier);

      final toggle = find.ancestor(
        of: find.text('Refresh and alerts'),
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
        of: find.text('Refresh and alerts'),
        matching: find.byType(SwitchListTile),
      );
      await tester.tap(find.descendant(of: toggle, matching: find.byType(Switch)));
      await settle(tester);

      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(find.textContaining('blocked'), findsOneWidget);
    });

    testWidgets('"Check now" posts what the screen holds', (tester) async {
      final notifier = FakeNotifier();
      await openSettings(tester, notifier);

      await tester.scrollUntilVisible(find.text('Check now'), 150);
      await settle(tester, frames: 4);
      await tester.tap(find.text('Check now'));
      // "Check now" downloads before it compares, so the fake clock and the
      // real one have to take turns until the file lands.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await settle(tester, frames: 10);
      }

      // Forced, so it posts even on a first run: one alert per ticker, with a
      // summary above them.
      expect(notifier.posted, isNotEmpty);
      expect(
        notifier.posted.map((n) => '${n.title} ${n.body}').join(' '),
        contains('MRNA'),
      );
    });

    testWidgets('tapping the digest while on another window does not crash', (
      tester,
    ) async {
      // The tap arrives as a notification from outside the tree, so the shell
      // has to act on it without touching state mid-build. It only ever threw
      // when the window actually changed, which is why the case below —
      // sitting on 1M when the digest lands — is the one that matters.
      final router = DigestRouter();
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        router: router,
        size: const Size(1440, 900),
        devicePixelRatio: 1.0,
      );

      final appState = Provider.of<AppState>(
        tester.element(find.byType(DesktopShell)),
        listen: false,
      );
      appState.selectWindow(GrowthWindow.oneMonth);
      await settle(tester);

      router.requestSevenDayList();
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(appState.selectedWindow, GrowthWindow.sevenDays);
      expect(find.byType(MarketListScreen), findsOneWidget);
      expect(router.showSevenDayList, isFalse);
    });

    testWidgets('the handset shell survives the same tap', (tester) async {
      // Both shells consume the request, and both are built inside AppShell's
      // LayoutBuilder, so the handset had the identical defect.
      final router = DigestRouter();
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: payloads,
        router: router,
      );

      final appState = Provider.of<AppState>(
        tester.element(find.byType(HomeShell)),
        listen: false,
      );
      appState.selectWindow(GrowthWindow.oneMonth);
      await settle(tester);

      router.requestSevenDayList();
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(appState.selectedWindow, GrowthWindow.sevenDays);
      expect(find.byType(MarketListScreen), findsOneWidget);
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
