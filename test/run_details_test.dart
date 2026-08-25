import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/market_database.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/models/market.dart';
import 'package:screener/models/run_details.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';
import 'support/fixture_database.dart';

/// The `run_metadata` and `screen_funnel` tables the pipeline publishes
/// alongside the growth tables.
void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('screener_run_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  const funnel = [
    FixtureStage(
      window: '7_days',
      position: 0,
      stage: 'Universe in window',
      count: 402,
    ),
    FixtureStage(
      window: '7_days',
      position: 1,
      stage: 'Enough span',
      count: 380,
    ),
    FixtureStage(
      window: '7_days',
      position: 2,
      stage: 'Return above 10.0%',
      count: 6,
    ),
    FixtureStage(
      window: '1_month',
      position: 0,
      stage: 'Universe in window',
      count: 402,
    ),
    FixtureStage(
      window: '1_month',
      position: 1,
      stage: 'Return above 10.0%',
      count: 16,
    ),
  ];

  Future<MarketDatabase> open({
    FixtureRun? run = const FixtureRun(),
    List<FixtureStage> stages = funnel,
  }) async {
    final path = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'us.db',
      tablePrefix: 'us_stocks_growth',
      includeConsistentTable: false,
      run: run,
      funnel: stages,
      rowsBySuffix: const {
        '_7_days': [
          FixtureRow(
            ticker: 'AAA',
            name: 'Alpha',
            exchange: 'NASDAQ',
            firstDate: '2026-08-14',
            firstPrice: 110,
            lastDate: '2026-08-21',
            latestPrice: 120,
            pctChange: 9.09,
          ),
        ],
      },
    );
    return MarketDatabase.open(Market.us, path);
  }

  test('discovers both tables by their columns', () async {
    final db = await open();
    addTearDown(db.close);

    expect(db.hasRunMetadata, isTrue);
    expect(db.hasScreenFunnel, isTrue);
  });

  test('a file without either table still opens', () async {
    final db = await open(run: null, stages: const []);
    addTearDown(db.close);

    expect(db.hasRunMetadata, isFalse);
    expect(db.hasScreenFunnel, isFalse);
    expect(await db.runMetadata(), isNull);
    expect(await db.screenFunnel(), isEmpty);
  });

  test('reads the run row, parsing its settings JSON', () async {
    final db = await open();
    addTearDown(db.close);

    final run = (await db.runMetadata())!;
    expect(run.runId, '20260822T224430Z-a4761276');
    expect(run.succeeded, isTrue);
    expect(run.universeTotal, 403);
    expect(run.universeScreened, 402);
    expect(run.provider, 'yahoo_finance');
    expect(run.settings['min_price'], 2.0);
    expect(run.headlineSettings, contains(('Minimum price', '2.0')));
    // The thresholds are named by the funnel stages, so they are not repeated.
    expect([
      for (final pair in run.headlineSettings) pair.$1,
    ], isNot(contains('windows')));
  });

  test('the run duration comes from both timestamps', () async {
    final db = await open();
    addTearDown(db.close);

    final run = (await db.runMetadata())!;
    expect(run.duration, const Duration(milliseconds: 1403, microseconds: 944));
  });

  test('a run missing its finish time reports no duration', () {
    final run = RunMetadata.fromMap(const {
      'run_id': 'r1',
      'status': 'failed',
      'started_at': '2026-08-22T22:44:30Z',
    });
    expect(run.duration, isNull);
    expect(run.succeeded, isFalse);
  });

  test('unparseable settings do not sink the row', () {
    final run = RunMetadata.fromMap(const {
      'run_id': 'r1',
      'status': 'success',
      'settings_json': 'not json',
    });
    expect(run.runId, 'r1');
    expect(run.settings, isEmpty);
    expect(run.headlineSettings, isEmpty);
  });

  test('funnel stages come back ordered, keyed to their window', () async {
    final db = await open();
    addTearDown(db.close);

    final stages = await db.screenFunnel();
    expect(stages, hasLength(5));

    final week = await db.screenFunnel(window: GrowthWindow.sevenDays);
    expect(
      [for (final s in week) s.stage],
      ['Universe in window', 'Enough span', 'Return above 10.0%'],
    );
    expect(week.last.count, 6);
    expect(week.first.window, GrowthWindow.sevenDays);

    final month = await db.screenFunnel(window: GrowthWindow.oneMonth);
    expect(month.last.count, 16);
  });

  test('the funnel bottom matches the rows actually published', () async {
    final db = await open(
      stages: const [
        FixtureStage(
          window: '7_days',
          position: 0,
          stage: 'Universe in window',
          count: 402,
        ),
        FixtureStage(
          window: '7_days',
          position: 1,
          stage: 'Return above 10.0%',
          count: 1,
        ),
      ],
    );
    addTearDown(db.close);

    final stages = await db.screenFunnel(window: GrowthWindow.sevenDays);
    final run = await db.runInfo(GrowthWindow.sevenDays);
    expect(stages.last.count, run!.rowCount);
  });

  test('a stage without a usable count is dropped', () {
    expect(
      FunnelStage.fromMap(const {'window': '7_days', 'stage': 'Enough span'}),
      isNull,
    );
    expect(FunnelStage.fromMap(const {'window': '7_days', 'count': 3}), isNull);
  });

  test('an unrecognised window leaves the stage unfiltered', () {
    final stage = FunnelStage.fromMap(const {
      'window': '2_weeks',
      'position': 0,
      'stage': 'Universe in window',
      'count': 5,
    })!;
    expect(stage.window, isNull);
    expect(stage.count, 5);
  });

  group('when the file was produced', () {
    test('prefers the run\'s finish over anything else', () async {
      final db = await open();
      addTearDown(db.close);

      // The fixture's run finished 1.4 seconds after it started.
      final run = (await db.runMetadata())!;
      expect(await db.publishedAt(), run.finishedAt!.toUtc());
      expect(await db.dataAsOf(), '2026-08-21');
    });

    test('falls back to the run id when there is no metadata table', () async {
      final db = await open(run: null, stages: const []);
      addTearDown(db.close);

      // 20260822T224430Z-a4761276, as the pipeline stamps them.
      expect(await db.publishedAt(), DateTime.utc(2026, 8, 22, 22, 44, 30));
      // And the date the rows themselves carry.
      expect(await db.dataAsOf(), '2026-08-21');
    });

    test('is null when the file carries no stamp at all', () async {
      final path = await createFixtureDatabase(
        directory: tempDir,
        fileName: 'bare.db',
        tablePrefix: 'us_stocks_growth',
        includeConsistentTable: false,
        rowsBySuffix: const {
          '_7_days': [
            FixtureRow(
              ticker: 'AAA',
              name: 'Alpha',
              exchange: 'NASDAQ',
              firstDate: '2026-08-14',
              firstPrice: 10,
              lastDate: '2026-08-21',
              latestPrice: 12,
              pctChange: 20,
              runId: 'not-a-stamp',
              dataAsOf: '',
            ),
          ],
        },
      );
      final bare = await MarketDatabase.open(Market.us, path);
      addTearDown(bare.close);

      expect(await bare.publishedAt(), isNull);
      expect(await bare.dataAsOf(), isNull);
    });
  });

  group('the metadata panel on screen', () {
    late Directory cacheDir;
    late Directory serveDir;
    late Map<String, List<int>> asxOnly;
    late Map<String, List<int>> bothMarkets;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cacheDir = await Directory.systemTemp.createTemp('screener_meta_cache');
      serveDir = await Directory.systemTemp.createTemp('screener_meta_serve');
      // Built here rather than in the test body: `testWidgets` runs in a
      // fake-async zone where real file I/O never completes.
      asxOnly = await buildFixturePayloads(serveDir);
      bothMarkets = await buildFixturePayloads(serveDir, metadataForUs: true);
    });

    tearDown(() async {
      for (final dir in [cacheDir, serveDir]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    Future<void> openReports(
      WidgetTester tester, {
      bool metadataForUs = false,
    }) async {
      await launchApp(
        tester,
        cacheDir: cacheDir,
        payloads: metadataForUs ? bothMarkets : asxOnly,
        size: const Size(1440, 900),
        devicePixelRatio: 1.0,
      );
      await tester.tap(find.text('Reports'));
      await settle(tester);
    }

    testWidgets('values are right-aligned, in line with each other', (
      tester,
    ) async {
      await openReports(tester);

      // Every value in a panel ends at the same edge; a value that stopped
      // where its label ended would sit hundreds of pixels short.
      final provider = tester.getBottomRight(find.text('yahoo_finance')).dx;
      final asOf = tester.getBottomRight(find.text('Aug 21, 2026')).dx;
      final universe = tester.getBottomRight(find.text('ASX · etf')).dx;
      expect(asOf, closeTo(provider, 0.5));
      expect(universe, closeTo(provider, 0.5));
    });

    testWidgets('a long value wraps instead of being truncated', (
      tester,
    ) async {
      await openReports(tester);

      // The run id is the longest value published and used to end in an
      // ellipsis, which cannot be read or copied.
      final id = find.text('20260823T090042Z-30ac6f5b');
      expect(id, findsOneWidget);
      final text = tester.widget<Text>(id);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.maxLines, isNull, reason: 'no line cap, so nothing is lost');
    });

    testWidgets('values are selectable', (tester) async {
      await openReports(tester);

      final id = find.text('20260823T090042Z-30ac6f5b');
      expect(
        SelectionContainer.maybeOf(tester.element(id)),
        isNotNull,
        reason: 'the value must sit inside the app-wide selection area',
      );
    });

    testWidgets('us.db gets the same panels once it publishes them', (
      tester,
    ) async {
      await openReports(tester, metadataForUs: true);

      // The ASX section renders its pair, as always.
      expect(find.text('Run metadata'), findsWidgets);

      // The US section, below it, now renders the same pair from its own run
      // rather than the note about publishing neither.
      await tester.scrollUntilVisible(find.text('US — us.db'), 300);
      await settle(tester, frames: 4);
      expect(find.text('20260823T053645Z-704684ee'), findsWidgets);
      expect(find.text('NASDAQ · common stock'), findsOneWidget);
      expect(find.text('Screen funnel'), findsWidgets);
      expect(find.textContaining('publishes no run metadata'), findsNothing);
    });
  });
}
