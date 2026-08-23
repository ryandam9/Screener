import '../models/stock_row.dart';

/// The published column order, reproduced exactly so an export round-trips
/// back into the same schema.
const List<String> kStockCsvHeader = [
  'ticker',
  'name',
  'exchange',
  'asset_type',
  'first_date',
  'first_price',
  'last_date',
  'latest_price',
  'pct_change',
  'observations',
  'days_covered',
  'coverage',
  'observation_ratio',
  'median_volume',
  'price_basis',
  'data_as_of',
  'run_id',
  'google_finance',
];

/// Escapes one CSV field per RFC 4180.
///
/// Company names carry commas and quotes ("Moderna, Inc. - Common Stock"), so
/// quoting is not optional here.
String csvField(Object? value) {
  final text = value?.toString() ?? '';
  final needsQuotes =
      text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r');
  if (!needsQuotes) return text;
  return '"${text.replaceAll('"', '""')}"';
}

/// Renders rows as CSV with the published header, newline terminated.
String stockRowsToCsv(Iterable<StockRow> rows) {
  final buffer = StringBuffer()..writeln(kStockCsvHeader.join(','));
  for (final row in rows) {
    buffer.writeln(
      [
        row.ticker,
        row.name,
        row.exchange,
        row.assetType,
        row.firstDate ?? '',
        row.firstPrice,
        row.lastDate ?? '',
        row.latestPrice,
        row.pctChange,
        row.observations,
        row.daysCovered,
        row.coverage,
        row.observationRatio,
        row.medianVolume,
        row.priceBasis,
        row.dataAsOf ?? '',
        row.runId ?? '',
        row.googleFinanceUrl ?? '',
      ].map(csvField).join(','),
    );
  }
  return buffer.toString();
}
