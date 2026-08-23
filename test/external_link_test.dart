import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/ui/screens/stock_detail_screen.dart';
import 'package:screener/ui/widgets/google_finance_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// `openExternalUrl` has to survive both ways url_launcher reports failure.
///
/// The launcher plugin is driven through its platform channel here, so the
/// test can make the channel throw — which is what a device with no browser
/// registered for https actually does, and what silently swallowed the tap
/// before this path was hardened.
void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpOpener(WidgetTester tester, String? url) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openExternalUrl(context, url),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('a launcher exception surfaces a message, not silence', (
    tester,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
    });

    await pumpOpener(
      tester,
      'https://www.google.com/finance/quote/MRNA:NASDAQ',
    );

    expect(find.text('Could not open the link'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('a false result also surfaces a message', (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'canLaunch') return true;
      return false;
    });

    await pumpOpener(
      tester,
      'https://www.google.com/finance/quote/MRNA:NASDAQ',
    );

    expect(find.text('Could not open the link'), findsOneWidget);
  });

  testWidgets('a successful launch stays quiet', (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => true,
    );

    await pumpOpener(
      tester,
      'https://www.google.com/finance/quote/MRNA:NASDAQ',
    );

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a row with no published link says so', (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => true,
    );

    await pumpOpener(tester, null);

    expect(find.text('This row has no link published'), findsOneWidget);
  });

  group('reaching the link without a menu', () {
    late Directory cacheDir;
    late Directory serveDir;
    late Map<String, List<int>> payloads;
    late List<String> launched;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cacheDir = await Directory.systemTemp.createTemp('screener_link_cache');
      serveDir = await Directory.systemTemp.createTemp('screener_link_serve');
      payloads = await buildFixturePayloads(serveDir);

      launched = [];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
    });

    tearDown(() async {
      for (final dir in [cacheDir, serveDir]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    testWidgets('a market list row opens Google Finance in one tap', (
      tester,
    ) async {
      await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
      await tester.tap(find.text('Markets').last);
      await settle(tester);

      final buttons = find.byType(GoogleFinanceButton);
      expect(buttons, findsWidgets, reason: 'every row publishes a link');

      await tester.tap(buttons.first);
      await settle(tester, frames: 6);

      expect(launched, hasLength(1));
      expect(launched.single, contains('google.com/finance/quote/MRNA'));
      expect(
        find.byType(StockDetailScreen),
        findsNothing,
        reason: 'the link must not also open the row',
      );
    });

    testWidgets('the detail header carries the link, not a menu', (
      tester,
    ) async {
      await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
      await tester.tap(find.text('MRNA').first);
      await settle(tester);
      expect(find.byType(StockDetailScreen), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(StockDetailScreen),
          matching: find.byType(GoogleFinanceButton),
        ),
      );
      await settle(tester, frames: 6);

      expect(launched, hasLength(1));
      expect(launched.single, contains('MRNA'));
    });
  });
}
