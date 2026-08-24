import 'package:flutter_test/flutter_test.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/models/market.dart';
import 'package:screener/models/stock_row.dart';
import 'package:screener/utils/csv.dart';

StockRow _row({
  String ticker = 'MRNA',
  String name = 'Moderna, Inc. - Common Stock',
  String? runId = '20260822T224430Z-a4761276',
}) {
  return StockRow(
    market: Market.us,
    window: GrowthWindow.sevenDays,
    ticker: ticker,
    name: name,
    exchange: 'NASDAQ',
    assetType: 'common_stock',
    firstDate: '2026-08-14',
    firstPrice: 63.89,
    lastDate: '2026-08-21',
    latestPrice: 139.225,
    pctChange: 117.91,
    threshold: 10,
    observations: 6,
    daysCovered: 7,
    coverage: 1,
    observationRatio: 1,
    medianVolume: 45924100,
    priceBasis: 'adjusted',
    dataAsOf: '2026-08-21',
    runId: runId,
    googleFinanceUrl: 'https://example.test/q',
  );
}

void main() {
  group('csvField', () {
    test('leaves plain values alone', () {
      expect(csvField('MRNA'), 'MRNA');
      expect(csvField(117.91), '117.91');
      expect(csvField(null), '');
    });

    test('quotes commas, quotes and newlines', () {
      // Company names carry commas, which is why quoting is not optional.
      expect(csvField('Moderna, Inc.'), '"Moderna, Inc."');
      expect(csvField('a"b'), '"a""b"');
      expect(csvField('line1\nline2'), '"line1\nline2"');
    });
  });

  group('stockRowsToCsv', () {
    test('writes the published header in schema order', () {
      final csv = stockRowsToCsv([_row()]);
      final header = csv.split('\n').first;

      expect(header, kStockCsvHeader.join(','));
      expect(header.startsWith('ticker,name,exchange,asset_type'), isTrue);
      expect(header.endsWith('run_id,google_finance'), isTrue);
    });

    test('emits one line per row, with the name quoted', () {
      final csv = stockRowsToCsv([_row(), _row(ticker: 'AMLX')]);
      final lines = csv.trim().split('\n');

      expect(lines, hasLength(3), reason: 'header plus two rows');
      expect(lines[1], contains('"Moderna, Inc. - Common Stock"'));
      expect(lines[1], startsWith('MRNA,'));
      expect(lines[2], startsWith('AMLX,'));
      expect(
        lines[1].split(',').length,
        greaterThanOrEqualTo(kStockCsvHeader.length),
      );
    });

    test('renders a null run id as an empty field, not "null"', () {
      final csv = stockRowsToCsv([_row(runId: null)]);
      expect(csv, isNot(contains('null')));
      expect(csv.trim().split('\n')[1], contains(',,'));
    });

    test('an empty list still produces the header', () {
      expect(stockRowsToCsv(const []).trim(), kStockCsvHeader.join(','));
    });
  });
}
