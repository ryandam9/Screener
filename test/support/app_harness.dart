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
Future<Map<String, List<int>>> buildFixturePayloads(Directory serveDir) async {
  final usPath = await createFixtureDatabase(
    directory: serveDir,
    fileName: 'us.db',
    tablePrefix: 'us_stocks_growth',
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
