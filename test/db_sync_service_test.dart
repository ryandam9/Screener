import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:screener/data/db_sync_service.dart';
import 'package:screener/models/market.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal valid SQLite header so the download passes validation.
List<int> sqliteBytes([int filler = 0]) => [
  ...'SQLite format 3'.codeUnits,
  0,
  ...List.filled(64, filler),
];

void main() {
  late Directory tempDir;
  late SharedPreferences prefs;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('screener_sync_test');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  DbSyncService serviceWith(MockClient client) => DbSyncService(
    preferences: prefs,
    client: client,
    directoryResolver: () async => tempDir,
  );

  test('builds the regional S3 url for each market', () {
    final service = serviceWith(
      MockClient((_) async => http.Response('', 200)),
    );
    expect(
      service.urlFor(Market.us).toString(),
      'https://hive-in-the-cloud.s3.ap-southeast-2.amazonaws.com/us.db',
    );
    expect(service.urlFor(Market.asx).toString(), endsWith('/asx.db'));
  });

  test('downloads and caches, recording the etag', () async {
    var requests = 0;
    final service = serviceWith(
      MockClient((request) async {
        requests++;
        return http.Response.bytes(
          sqliteBytes(),
          200,
          headers: {'etag': '"v1"'},
        );
      }),
    );

    final asset = await service.sync(Market.us);
    expect(requests, 1);
    expect(asset.etag, '"v1"');
    expect(File(asset.path).existsSync(), isTrue);

    final cached = await service.cached(Market.us);
    expect(cached?.etag, '"v1"');
    expect(cached?.sizeBytes, asset.sizeBytes);
  });

  test('sends If-None-Match and keeps the file on 304', () async {
    var call = 0;
    String? conditionalHeader;
    final service = serviceWith(
      MockClient((request) async {
        call++;
        if (call == 1) {
          return http.Response.bytes(
            sqliteBytes(1),
            200,
            headers: {'etag': '"v1"'},
          );
        }
        conditionalHeader = request.headers['If-None-Match'];
        return http.Response('', 304);
      }),
    );

    final first = await service.sync(Market.us);
    final second = await service.sync(Market.us);

    expect(conditionalHeader, '"v1"');
    expect(second.etag, '"v1"');
    expect(second.sizeBytes, first.sizeBytes);
    expect(File(first.path).readAsBytesSync().length, sqliteBytes().length);
  });

  test('force skips the conditional headers', () async {
    var sentConditional = false;
    final service = serviceWith(
      MockClient((request) async {
        if (request.headers.containsKey('If-None-Match')) {
          sentConditional = true;
        }
        return http.Response.bytes(
          sqliteBytes(),
          200,
          headers: {'etag': '"v1"'},
        );
      }),
    );

    await service.sync(Market.us);
    await service.sync(Market.us, force: true);
    expect(sentConditional, isFalse);
  });

  test('rejects a 200 that is not a SQLite file and keeps the cache', () async {
    var call = 0;
    final service = serviceWith(
      MockClient((request) async {
        call++;
        if (call == 1) {
          return http.Response.bytes(
            sqliteBytes(),
            200,
            headers: {'etag': '"v1"'},
          );
        }
        // S3 can answer 200 with an XML error document.
        return http.Response('<?xml version="1.0"?><Error/>', 200);
      }),
    );

    final good = await service.sync(Market.us);
    await expectLater(
      service.sync(Market.us, force: true),
      throwsA(isA<DbSyncException>()),
    );

    expect(
      File(good.path).existsSync(),
      isTrue,
      reason: 'a bad download must not destroy the working copy',
    );
    expect(File('${good.path}.part').existsSync(), isFalse);
  });

  test('surfaces a non-200 response', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('nope', 403)),
    );
    await expectLater(
      service.sync(Market.us),
      throwsA(
        isA<DbSyncException>().having(
          (e) => e.message,
          'message',
          contains('403'),
        ),
      ),
    );
  });

  test('reports download progress', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response.bytes(sqliteBytes(), 200)),
    );

    final stages = <DownloadStage>[];
    await service.sync(Market.us, onProgress: (p) => stages.add(p.stage));

    expect(stages.first, DownloadStage.checking);
    expect(stages, contains(DownloadStage.downloading));
    expect(stages.last, DownloadStage.done);
  });

  test('clearing the cache removes the file and its metadata', () async {
    final service = serviceWith(
      MockClient(
        (_) async =>
            http.Response.bytes(sqliteBytes(), 200, headers: {'etag': '"v1"'}),
      ),
    );

    final asset = await service.sync(Market.us);
    await service.deleteCache(Market.us);

    expect(File(asset.path).existsSync(), isFalse);
    expect(await service.cached(Market.us), isNull);
  });

  test('a custom base url overrides the default and can be reset', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('', 200)),
    );

    await service.setBaseUrl('https://example.test/data/');
    expect(
      service.urlFor(Market.asx).toString(),
      'https://example.test/data/asx.db',
    );

    await service.setBaseUrl('');
    expect(service.baseUrl, kDefaultBaseUrl);
  });
}
