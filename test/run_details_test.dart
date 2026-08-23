import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/market_database.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/models/market.dart';
import 'package:screener/models/run_details.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
}
