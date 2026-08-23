import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/csv_export.dart';
import 'package:screener/data/market_database.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/models/market.dart';
import 'package:screener/utils/csv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fixture_database.dart';

/// The Reports export, end to end: query the database, render CSV, write it.
///
/// The destination is injected so this covers the real write path without a
/// platform channel for the Downloads folder.
void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('screener_export_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<MarketDatabase> openFixture() async {
    final path = await createFixtureDatabase(
      directory: tempDir,
      fileName: 'us.db',
      tablePrefix: 'us_stocks_growth',
      includeConsistentTable: false,
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
      },
    );
    return MarketDatabase.open(Market.us, path);
  }

  test('writes a named CSV file with a header and every row', () async {
    final db = await openFixture();
    addTearDown(db.close);
    final out = Directory('${tempDir.path}/out');

    final file = await exportWindowCsv(
      db,
      GrowthWindow.sevenDays,
      destination: out,
    );

    expect(file.existsSync(), isTrue);
    expect(file.path, endsWith('screener-us-sevenDays.csv'));

    final lines = file.readAsStringSync().trim().split('\n');
    expect(lines.first, kStockCsvHeader.join(','));
    expect(lines, hasLength(3), reason: 'header plus both rows');
    expect(lines[1], startsWith('MRNA,'));
    expect(lines[1], contains('"Moderna, Inc. - Common Stock"'));
    expect(lines[2], startsWith('AMLX,'));
  });

  test('creates the destination folder when it does not exist', () async {
    final db = await openFixture();
    addTearDown(db.close);
    // Nested and absent, like a fresh account with no Downloads folder.
    final out = Directory('${tempDir.path}/nope/still-nope');
    expect(out.existsSync(), isFalse);

    final file = await exportWindowCsv(
      db,
      GrowthWindow.sevenDays,
      destination: out,
    );

    expect(file.existsSync(), isTrue);
    expect(out.existsSync(), isTrue);
  });

  test('an empty window still writes a header-only file', () async {
    final db = await openFixture();
    addTearDown(db.close);

    final file = await exportWindowCsv(
      db,
      GrowthWindow.oneYear,
      destination: tempDir,
    );

    expect(file.readAsStringSync().trim(), kStockCsvHeader.join(','));
  });

  test('overwrites a previous export rather than appending', () async {
    final db = await openFixture();
    addTearDown(db.close);

    final first = await exportWindowCsv(
      db,
      GrowthWindow.sevenDays,
      destination: tempDir,
    );
    final firstLength = first.readAsStringSync().length;

    final second = await exportWindowCsv(
      db,
      GrowthWindow.sevenDays,
      destination: tempDir,
    );

    expect(second.path, first.path);
    expect(second.readAsStringSync().length, firstLength);
  });
}
