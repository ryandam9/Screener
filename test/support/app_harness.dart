import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:screener/data/db_sync_service.dart';
import 'package:screener/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture_database.dart';

/// Drives the whole app against fixture databases served by a fake S3.
///
/// Two testing constraints shape this. `testWidgets` runs its body in a
/// fake-async zone, where the sync service's real file I/O and sqflite's FFI
/// calls never complete, so [settle] hands time back to the real event loop via
/// `runAsync` between frames. And `pumpAndSettle` cannot be used at all: the
/// loading and download indicators animate continuously and would keep it
/// spinning until its timeout.
Future<void> settle(WidgetTester tester, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 8)),
    );
  }
}

/// Builds `us.db` and `asx.db` fixtures and returns their bytes, ready to be
/// served to the sync service.
///
/// Call from `setUp`, which runs outside the fake-async zone, so ordinary
/// async I/O completes.
Future<Map<String, List<int>>> buildFixturePayloads(
  Directory serveDir, {

  /// Publishes run metadata and a funnel in `us.db` too. In production only
  /// `asx.db` carries them, which is what the default reproduces.
  bool metadataForUs = false,
}) async {
  // Six Fridays of history, enough for the charts to have a real shape.
  const usBars = [
    FixtureBar(date: '2026-07-17', ticker: 'MRNA', close: 57.10),
    FixtureBar(date: '2026-07-24', ticker: 'MRNA', close: 60.40),
    FixtureBar(date: '2026-07-31', ticker: 'MRNA', close: 59.20),
    FixtureBar(date: '2026-08-07', ticker: 'MRNA', close: 62.75),
    FixtureBar(date: '2026-08-14', ticker: 'MRNA', close: 63.89),
    FixtureBar(date: '2026-08-21', ticker: 'MRNA', close: 139.225),
    FixtureBar(date: '2026-08-14', ticker: 'AMLX', close: 21.53),
    FixtureBar(date: '2026-08-21', ticker: 'AMLX', close: 39.16),
  ];
  const asxBars = [
    FixtureBar(date: '2026-07-17', ticker: 'QETH', close: 15.80),
    FixtureBar(date: '2026-07-24', ticker: 'QETH', close: 16.40),
    FixtureBar(date: '2026-07-31', ticker: 'QETH', close: 17.05),
    FixtureBar(date: '2026-08-07', ticker: 'QETH', close: 17.90),
    FixtureBar(date: '2026-08-14', ticker: 'QETH', close: 18.53),
    FixtureBar(date: '2026-08-21', ticker: 'QETH', close: 22.42),
  ];

  final usPath = await createFixtureDatabase(
    directory: serveDir,
    fileName: 'us.db',
    tablePrefix: 'us_stocks_growth',
    weeklyBars: usBars,
    run: metadataForUs
        ? const FixtureRun(
            runId: '20260823T053645Z-704684ee',
            exchange: 'NASDAQ',
            instrumentType: 'common_stock',
          )
        : null,
    funnel: metadataForUs
        ? const [
            FixtureStage(
              window: '7_days',
              position: 0,
              stage: 'Universe in window',
              count: 4100,
            ),
            FixtureStage(
              window: '7_days',
              position: 1,
              stage: 'Return above 10.0%',
              count: 107,
            ),
          ]
        : const [],
    consistent: const [
      ('MRNA', 'Moderna, Inc. - Common Stock', 'NASDAQ', 117.91),
    ],
    rowsBySuffix: const {
      '_7_days': [
        FixtureRow(
          ticker: 'MRNA',
          name: 'Moderna, Inc. - Common Stock',
          exchange: 'NASDAQ',
          firstDate: '2026-08-14',
          firstPrice: 63.89,
          lastDate: '2026-08-21',
          latestPrice: 139.225,
          pctChange: 117.91,
          medianVolume: 45924100,
        ),
        FixtureRow(
          ticker: 'AMLX',
          name: 'Amylyx Pharmaceuticals, Inc. - Common Stock',
          exchange: 'NASDAQ',
          firstDate: '2026-08-14',
          firstPrice: 21.53,
          lastDate: '2026-08-21',
          latestPrice: 39.16,
          pctChange: 81.89,
          medianVolume: 6451750,
        ),
      ],
      '_1_month': [
        FixtureRow(
          ticker: 'MRNA',
          name: 'Moderna, Inc. - Common Stock',
          exchange: 'NASDAQ',
          firstDate: '2026-07-21',
          firstPrice: 58.07,
          lastDate: '2026-08-21',
          latestPrice: 145.13,
          pctChange: 149.92,
          observations: 24,
          daysCovered: 31,
          medianVolume: 5170000,
        ),
      ],
      '_1_year': [
        FixtureRow(
          ticker: 'MRNA',
          name: 'Moderna, Inc. - Common Stock',
          exchange: 'NASDAQ',
          firstDate: '2025-08-22',
          firstPrice: 25.35,
          lastDate: '2026-08-21',
          latestPrice: 145.13,
          pctChange: 472.5,
          threshold: 25,
          observations: 251,
          daysCovered: 364,
          medianVolume: 8359900,
        ),
      ],
    },
  );

  final asxPath = await createFixtureDatabase(
    directory: serveDir,
    fileName: 'asx.db',
    tablePrefix: 'asx_etf_growth',
    includeConsistentTable: false,
    weeklyBars: asxBars,
    // Only the ASX file carries these tables, mirroring production: the app
    // has to show them where they exist and say so where they do not.
    run: const FixtureRun(
      runId: '20260823T090042Z-30ac6f5b',
      exchange: 'ASX',
      instrumentType: 'etf',
    ),
    funnel: const [
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
        stage: 'Liquid enough',
        count: 210,
      ),
      FixtureStage(
        window: '7_days',
        position: 3,
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
        stage: 'Enough span',
        count: 395,
      ),
      FixtureStage(
        window: '1_month',
        position: 2,
        stage: 'Liquid enough',
        count: 230,
      ),
      FixtureStage(
        window: '1_month',
        position: 3,
        stage: 'Return above 10.0%',
        count: 16,
      ),
    ],
    rowsBySuffix: const {
      '_7_days': [
        FixtureRow(
          ticker: 'QETH',
          name: 'Betashares Ethereum ETF',
          exchange: 'ASX',
          assetType: 'etf',
          firstDate: '2026-08-14',
          firstPrice: 18.53,
          lastDate: '2026-08-21',
          latestPrice: 22.42,
          pctChange: 20.99,
          medianVolume: 7518,
        ),
      ],
      '_1_month': [
        FixtureRow(
          ticker: 'QETH',
          name: 'Betashares Ethereum ETF',
          exchange: 'ASX',
          assetType: 'etf',
          firstDate: '2026-07-21',
          firstPrice: 16.10,
          lastDate: '2026-08-21',
          latestPrice: 22.42,
          pctChange: 39.25,
          observations: 22,
          daysCovered: 31,
          medianVolume: 8100,
        ),
      ],
    },
  );

  return {
    'us.db': await File(usPath).readAsBytes(),
    'asx.db': await File(asxPath).readAsBytes(),
  };
}

/// A sync service backed by [payloads] instead of S3.
DbSyncService fixtureSyncService({
  required SharedPreferences preferences,
  required Directory cacheDir,
  required Map<String, List<int>> payloads,
  bool Function()? shouldFail,
}) {
  return DbSyncService(
    preferences: preferences,
    directoryResolver: () async => cacheDir,
    client: MockClient((request) async {
      if (shouldFail?.call() ?? false) {
        return http.Response('server error', 500);
      }
      final name = request.url.pathSegments.last;
      final bytes = payloads[name];
      if (bytes == null) return http.Response('not found', 404);
      return http.Response.bytes(bytes, 200, headers: {'etag': '"$name-1"'});
    }),
  );
}

/// Starts the app at [size] and waits for the first render.
Future<SharedPreferences> launchApp(
  WidgetTester tester, {
  required Directory cacheDir,
  required Map<String, List<int>> payloads,
  Size size = const Size(1080, 2340),
  double devicePixelRatio = 3.0,
  bool Function()? shouldFail,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);

  late SharedPreferences prefs;
  await tester.runAsync(() async {
    prefs = await SharedPreferences.getInstance();
  });

  await tester.pumpWidget(
    ScreenerApp(
      preferences: prefs,
      syncService: fixtureSyncService(
        preferences: prefs,
        cacheDir: cacheDir,
        payloads: payloads,
        shouldFail: shouldFail,
      ),
    ),
  );
  await settle(tester);
  return prefs;
}
