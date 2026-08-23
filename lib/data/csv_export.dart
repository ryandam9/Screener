import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/growth_window.dart';
import '../utils/csv.dart';
import 'market_database.dart';

/// Writes one window of a market to a CSV file and returns it.
///
/// Kept out of the widget so the whole path — query, render, write — can be
/// tested without a platform channel: pass [destination] to choose the folder,
/// or leave it null to use the platform's Downloads folder (falling back to the
/// documents folder on platforms that have none).
Future<File> exportWindowCsv(
  MarketDatabase database,
  GrowthWindow window, {
  Directory? destination,
}) async {
  final rows = await database.stocks(window);
  final directory =
      destination ??
      await getDownloadsDirectory() ??
      await getApplicationDocumentsDirectory();

  final file = File(
    p.join(directory.path, 'screener-${database.market.id}-${window.name}.csv'),
  );
  // A fresh account may have no Downloads folder yet.
  await file.parent.create(recursive: true);
  await file.writeAsString(stockRowsToCsv(rows));
  return file;
}
