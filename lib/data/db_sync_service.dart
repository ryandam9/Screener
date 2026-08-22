import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/market.dart';

/// Default public endpoint for `s3://hive-in-the-cloud`.
///
/// The bucket lives in ap-southeast-2; the regional host avoids the 301 the
/// generic `s3.amazonaws.com` host returns for buckets outside us-east-1.
const String kDefaultBaseUrl =
    'https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com';

class DbSyncException implements Exception {
  DbSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A market database on local disk, plus what we know about its origin.
class DbAsset {
  const DbAsset({
    required this.market,
    required this.path,
    required this.sizeBytes,
    required this.syncedAt,
    this.etag,
    this.lastModified,
  });

  final Market market;
  final String path;
  final int sizeBytes;
  final DateTime syncedAt;
  final String? etag;
  final String? lastModified;

  Map<String, Object?> toJson() => {
    'sizeBytes': sizeBytes,
    'syncedAt': syncedAt.toIso8601String(),
    'etag': etag,
    'lastModified': lastModified,
  };

  static DbAsset? fromJson(
    Map<String, Object?> json, {
    required Market market,
    required String path,
  }) {
    final syncedAt = DateTime.tryParse(json['syncedAt'] as String? ?? '');
    if (syncedAt == null) return null;
    return DbAsset(
      market: market,
      path: path,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      syncedAt: syncedAt,
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] as String?,
    );
  }
}

enum DownloadStage { checking, downloading, upToDate, done }

class DownloadProgress {
  const DownloadProgress(this.stage, {this.received = 0, this.total});

  final DownloadStage stage;
  final int received;
  final int? total;

  /// 0..1 when the server sent a content length, otherwise null.
  double? get fraction {
    final total = this.total;
    if (total == null || total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }
}

/// Downloads the published SQLite files and keeps them cached on device.
///
/// The app is offline-first: a cached file is always usable, and a refresh is
/// a conditional GET that leaves the cache untouched when S3 reports 304.
class DbSyncService {
  DbSyncService({
    required SharedPreferences preferences,
    http.Client? client,
    Future<Directory> Function()? directoryResolver,
  }) : _prefs = preferences,
       _client = client ?? http.Client(),
       _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final SharedPreferences _prefs;
  final http.Client _client;
  final Future<Directory> Function() _directoryResolver;

  static const _metaPrefix = 'db_meta_';
  static const _baseUrlKey = 'db_base_url';

  /// First bytes of every SQLite 3 file, used to reject error pages that S3
  /// may return with a 200 status.
  static const _sqliteMagic = 'SQLite format 3';

  String get baseUrl => _prefs.getString(_baseUrlKey) ?? kDefaultBaseUrl;

  Future<void> setBaseUrl(String value) async {
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty || trimmed == kDefaultBaseUrl) {
      await _prefs.remove(_baseUrlKey);
    } else {
      await _prefs.setString(_baseUrlKey, trimmed);
    }
  }

  Uri urlFor(Market market) => Uri.parse('$baseUrl/${market.objectKey}');

  Future<Directory> _databaseDirectory() async {
    final base = await _directoryResolver();
    final dir = Directory(p.join(base.path, 'markets'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> localPath(Market market) async {
    final dir = await _databaseDirectory();
    return p.join(dir.path, market.objectKey);
  }

  /// The cached copy, or null when nothing has been downloaded yet.
  Future<DbAsset?> cached(Market market) async {
    final path = await localPath(market);
    final file = File(path);
    if (!await file.exists()) return null;

    final raw = _prefs.getString('$_metaPrefix${market.id}');
    final size = await file.length();
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, Object?>;
        final asset = DbAsset.fromJson(decoded, market: market, path: path);
        if (asset != null) return asset;
      } on FormatException {
        // Corrupt metadata is not worth failing over; fall through to stat.
      }
    }
    return DbAsset(
      market: market,
      path: path,
      sizeBytes: size,
      syncedAt: await file.lastModified(),
    );
  }

  /// Fetches [market] unless the cached copy is still current.
  ///
  /// Set [force] to bypass the conditional headers and always re-download.
  Future<DbAsset> sync(
    Market market, {
    bool force = false,
    void Function(DownloadProgress)? onProgress,
  }) async {
    final path = await localPath(market);
    final file = File(path);
    final existing = await cached(market);

    onProgress?.call(const DownloadProgress(DownloadStage.checking));

    final request = http.Request('GET', urlFor(market));
    if (!force && existing != null && await file.exists()) {
      if (existing.etag != null) {
        request.headers['If-None-Match'] = existing.etag!;
      } else if (existing.lastModified != null) {
        request.headers['If-Modified-Since'] = existing.lastModified!;
      }
    }

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on SocketException catch (error) {
      throw DbSyncException(
        'No connection to ${urlFor(market).host} (${error.osError?.message ?? 'network unreachable'}).',
      );
    } on http.ClientException catch (error) {
      throw DbSyncException('Download failed: ${error.message}');
    }

    if (response.statusCode == 304 && existing != null) {
      onProgress?.call(const DownloadProgress(DownloadStage.upToDate));
      final refreshed = DbAsset(
        market: market,
        path: path,
        sizeBytes: existing.sizeBytes,
        syncedAt: DateTime.now(),
        etag: existing.etag,
        lastModified: existing.lastModified,
      );
      await _writeMeta(refreshed);
      return refreshed;
    }

    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw DbSyncException(
        'S3 returned HTTP ${response.statusCode} for ${market.objectKey}.',
      );
    }

    final total = response.contentLength;
    final temp = File('$path.part');
    if (await temp.exists()) await temp.delete();
    final sink = temp.openWrite();
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          DownloadProgress(
            DownloadStage.downloading,
            received: received,
            total: total,
          ),
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (!await _looksLikeSqlite(temp)) {
      await temp.delete();
      throw DbSyncException(
        '${market.objectKey} did not download as a SQLite database. '
        'Check the data source URL.',
      );
    }

    if (await file.exists()) await file.delete();
    await temp.rename(path);

    final asset = DbAsset(
      market: market,
      path: path,
      sizeBytes: received,
      syncedAt: DateTime.now(),
      etag: response.headers['etag'],
      lastModified: response.headers['last-modified'],
    );
    await _writeMeta(asset);
    onProgress?.call(const DownloadProgress(DownloadStage.done));
    return asset;
  }

  Future<void> deleteCache(Market market) async {
    final path = await localPath(market);
    final file = File(path);
    if (await file.exists()) await file.delete();
    await _prefs.remove('$_metaPrefix${market.id}');
  }

  Future<void> _writeMeta(DbAsset asset) => _prefs.setString(
    '$_metaPrefix${asset.market.id}',
    jsonEncode(asset.toJson()),
  );

  static Future<bool> _looksLikeSqlite(File file) async {
    final length = await file.length();
    if (length < 16) return false;
    final handle = await file.open();
    try {
      final header = await handle.read(_sqliteMagic.length);
      return String.fromCharCodes(header) == _sqliteMagic;
    } finally {
      await handle.close();
    }
  }

  void dispose() => _client.close();
}
