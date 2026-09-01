import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screener/data/db_sync_service.dart';
import 'package:screener/models/market.dart';
import 'package:screener/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingSyncService extends DbSyncService {
  _RecordingSyncService(SharedPreferences preferences)
    : super(
        preferences: preferences,
        directoryResolver: () async => Directory.systemTemp,
      );

  final List<bool> forceDownloads = [];

  @override
  Future<DbAsset> sync(
    Market market, {
    bool force = false,
    void Function(DownloadProgress)? onProgress,
  }) async {
    forceDownloads.add(force);
    throw DbSyncException('Expected test stop');
  }
}

void main() {
  test(
    'normal refresh revalidates while re-download bypasses the cache',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final sync = _RecordingSyncService(preferences);
      final state = AppState(syncService: sync);
      addTearDown(state.dispose);
      addTearDown(sync.dispose);

      await state.refreshAll();
      expect(sync.forceDownloads, hasLength(Market.values.length));
      expect(sync.forceDownloads.every((forced) => !forced), isTrue);

      sync.forceDownloads.clear();
      await state.redownloadAll();
      expect(sync.forceDownloads, hasLength(Market.values.length));
      expect(sync.forceDownloads.every((forced) => forced), isTrue);
    },
  );
}
