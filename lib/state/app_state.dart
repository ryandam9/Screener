import 'package:flutter/foundation.dart';

import '../data/db_sync_service.dart';
import '../data/market_database.dart';
import '../models/growth_window.dart';
import '../models/market.dart';

enum SyncPhase { idle, checking, downloading, opening, ready, error }

/// Sync + open state for a single market.
class MarketState {
  const MarketState({
    this.phase = SyncPhase.idle,
    this.progress,
    this.error,
    this.database,
    this.asset,
    this.usingCache = false,
    this.publishedAt,
    this.dataAsOf,
  });

  final SyncPhase phase;

  /// 0..1 while downloading, null when the length is unknown.
  final double? progress;
  final String? error;
  final MarketDatabase? database;
  final DbAsset? asset;

  /// True when the data on screen came from disk after a failed refresh.
  final bool usingCache;

  /// When the run that produced this file finished, from its own metadata —
  /// not when this device downloaded it.
  final DateTime? publishedAt;

  /// The date the prices are as of, as published.
  final String? dataAsOf;

  bool get isReady => phase == SyncPhase.ready && database != null;
  bool get isBusy =>
      phase == SyncPhase.checking ||
      phase == SyncPhase.downloading ||
      phase == SyncPhase.opening;

  MarketState copyWith({
    SyncPhase? phase,
    double? progress,
    String? error,
    MarketDatabase? database,
    DbAsset? asset,
    bool? usingCache,
    DateTime? publishedAt,
    String? dataAsOf,
    bool clearError = false,
    bool clearProgress = false,
  }) {
    return MarketState(
      phase: phase ?? this.phase,
      progress: clearProgress ? null : (progress ?? this.progress),
      error: clearError ? null : (error ?? this.error),
      database: database ?? this.database,
      asset: asset ?? this.asset,
      usingCache: usingCache ?? this.usingCache,
      publishedAt: publishedAt ?? this.publishedAt,
      dataAsOf: dataAsOf ?? this.dataAsOf,
    );
  }
}

/// Owns the market databases and the currently selected market/window.
///
/// Startup is offline-first: any cached file is opened and shown immediately,
/// then a conditional refresh runs in the background. A refresh that fails
/// never takes working data away — the cached database stays open and the UI
/// is told it is looking at cached data.
class AppState extends ChangeNotifier {
  AppState({required DbSyncService syncService}) : _sync = syncService;

  final DbSyncService _sync;
  final Map<Market, MarketState> _markets = {
    for (final market in Market.values) market: const MarketState(),
  };

  Market _selectedMarket = Market.us;
  GrowthWindow _selectedWindow = GrowthWindow.sevenDays;
  bool _initialised = false;

  DbSyncService get syncService => _sync;
  Market get selectedMarket => _selectedMarket;
  GrowthWindow get selectedWindow => _selectedWindow;
  bool get initialised => _initialised;

  MarketState stateOf(Market market) => _markets[market]!;
  MarketDatabase? databaseOf(Market market) => _markets[market]!.database;
  MarketDatabase? get selectedDatabase => databaseOf(_selectedMarket);

  bool get anyReady => Market.values.any((m) => stateOf(m).isReady);
  bool get allReady => Market.values.every((m) => stateOf(m).isReady);
  bool get anyBusy => Market.values.any((m) => stateOf(m).isBusy);

  /// Windows present in the selected market's file, falling back to all of
  /// them before the database is open.
  List<GrowthWindow> get availableWindows {
    final db = selectedDatabase;
    if (db == null) return GrowthWindow.values;
    final windows = db.availableWindows;
    return windows.isEmpty ? GrowthWindow.values : windows;
  }

  void selectMarket(Market market) {
    if (_selectedMarket == market) return;
    _selectedMarket = market;
    _ensureWindowAvailable();
    notifyListeners();
  }

  void selectWindow(GrowthWindow window) {
    if (_selectedWindow == window) return;
    _selectedWindow = window;
    notifyListeners();
  }

  void _ensureWindowAvailable() {
    final windows = availableWindows;
    if (!windows.contains(_selectedWindow) && windows.isNotEmpty) {
      _selectedWindow = windows.first;
    }
  }

  /// Opens caches first, then refreshes every market in parallel.
  Future<void> initialise() async {
    if (_initialised) return;
    _initialised = true;
    await Future.wait(Market.values.map(_openCached));
    await Future.wait(Market.values.map((m) => refresh(m)));
  }

  Future<void> _openCached(Market market) async {
    final cached = await _sync.cached(market);
    if (cached == null) return;
    try {
      final database = await MarketDatabase.open(market, cached.path);
      _set(
        market,
        MarketState(
          phase: SyncPhase.ready,
          database: database,
          asset: cached,
          usingCache: true,
          publishedAt: await database.publishedAt(),
          dataAsOf: await database.dataAsOf(),
        ),
      );
      _ensureWindowAvailable();
    } on Object {
      // A corrupt cache is replaced by the refresh that follows.
      await _sync.deleteCache(market);
    }
  }

  Future<void> refreshAll({bool force = false}) async {
    await Future.wait(Market.values.map((m) => refresh(m, force: force)));
  }

  /// Fetches [market] and reopens it if the bytes changed.
  Future<void> refresh(Market market, {bool force = false}) async {
    final previous = stateOf(market);
    if (previous.isBusy) return;

    _set(
      market,
      previous.copyWith(phase: SyncPhase.checking, clearError: true),
    );

    try {
      final asset = await _sync.sync(
        market,
        force: force,
        onProgress: (progress) {
          final current = stateOf(market);
          switch (progress.stage) {
            case DownloadStage.checking:
              break;
            case DownloadStage.downloading:
              _set(
                market,
                current.copyWith(
                  phase: SyncPhase.downloading,
                  progress: progress.fraction,
                ),
              );
            case DownloadStage.upToDate:
            case DownloadStage.done:
              _set(
                market,
                current.copyWith(phase: SyncPhase.opening, clearProgress: true),
              );
          }
        },
      );

      final current = stateOf(market);
      final unchanged =
          current.database != null &&
          current.asset != null &&
          current.asset!.etag != null &&
          current.asset!.etag == asset.etag;

      if (unchanged) {
        _set(
          market,
          current.copyWith(
            phase: SyncPhase.ready,
            asset: asset,
            usingCache: false,
            clearProgress: true,
          ),
        );
        return;
      }

      _set(market, current.copyWith(phase: SyncPhase.opening));
      await current.database?.close();
      final database = await MarketDatabase.open(market, asset.path);
      _set(
        market,
        MarketState(
          phase: SyncPhase.ready,
          database: database,
          asset: asset,
          usingCache: false,
          // Read while the file is being opened: the dashboard shows the run's
          // own stamp, and asking per rebuild would re-query on every frame.
          publishedAt: await database.publishedAt(),
          dataAsOf: await database.dataAsOf(),
        ),
      );
      _ensureWindowAvailable();
    } on Object catch (error) {
      final current = stateOf(market);
      // Keep serving whatever is already open.
      _set(
        market,
        current.copyWith(
          phase: current.database != null ? SyncPhase.ready : SyncPhase.error,
          error: error.toString(),
          usingCache: current.database != null,
          clearProgress: true,
        ),
      );
    }
  }

  void _set(Market market, MarketState state) {
    _markets[market] = state;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final state in _markets.values) {
      state.database?.close();
    }
    super.dispose();
  }
}
