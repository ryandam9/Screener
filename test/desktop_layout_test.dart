import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/ui/desktop/desktop_shell.dart';
import 'package:screener/ui/widgets/info_dialog.dart';
import 'package:screener/ui/widgets/panels.dart';
import 'package:screener/ui/screens/home_shell.dart';
import 'package:screener/ui/screens/stock_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// The desktop layout, driven end to end against the fixture databases.
void main() {
  late Directory cacheDir;
  late Directory serveDir;
  late Map<String, List<int>> payloads;

  // 1440x900 logical, which is what the Linux window opens near.
  const desktopSize = Size(1440, 900);
  const handsetSize = Size(1080, 2340);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('screener_desktop_cache');
    serveDir = await Directory.systemTemp.createTemp('screener_desktop_serve');
    SharedPreferences.setMockInitialValues({});
    payloads = await buildFixturePayloads(serveDir);
  });

  tearDown(() async {
    for (final dir in [cacheDir, serveDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  Future<void> launchDesktop(WidgetTester tester) => launchApp(
    tester,
    cacheDir: cacheDir,
    payloads: payloads,
    size: desktopSize,
    devicePixelRatio: 1.0,
  ).then((_) {});

  testWidgets('a wide window gets the sidebar layout', (tester) async {
    await launchDesktop(tester);

    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);

    // Every sidebar destination, including the desktop-only Reports.
    for (final label in [
      'Dashboard',
      'Markets',
      'Watchlist',
      'Analysis',
      'Reports',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets, reason: '$label missing');
    }
  });

  testWidgets('a narrow window keeps the handset layout', (tester) async {
    await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
      size: handsetSize,
    );

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(DesktopShell), findsNothing);
    expect(find.text('Reports'), findsNothing);
  });

  testWidgets('the dashboard renders its cards and the gainers table', (
    tester,
  ) async {
    await launchDesktop(tester);

    expect(find.text('ASX Market'), findsOneWidget);
    expect(find.text('US Market'), findsOneWidget);
    expect(find.text('Watchlist Performance'), findsOneWidget);
    expect(find.text('Analysis Summary'), findsOneWidget);

    // Table headings from the design.
    for (final heading in ['Ticker', 'Market', 'Price', 'Change', '% Gain']) {
      expect(find.text(heading), findsWidgets, reason: '$heading missing');
    }

    // Real fixture values, not placeholders.
    expect(find.text('MRNA'), findsWidgets);
    // The panel under the table charts the selected security.
    expect(find.textContaining('Moderna'), findsWidgets);
    expect(find.text('Open details'), findsOneWidget);
    expect(find.textContaining('weekly closes'), findsOneWidget);
    expect(find.text('Recent Analyses'), findsOneWidget);
  });

  testWidgets('the analysis summary refuses to invent a prior run', (
    tester,
  ) async {
    await launchDesktop(tester);

    expect(find.text('One published run'), findsOneWidget);
    expect(find.text('no earlier run to compare against'), findsOneWidget);
  });

  testWidgets('the sidebar switches sections', (tester) async {
    await launchDesktop(tester);

    await tester.tap(find.text('Reports'));
    await settle(tester);
    expect(find.textContaining('asx.db'), findsWidgets);
    expect(find.text('CSV'), findsWidgets);

    await tester.tap(find.text('Analysis'));
    await settle(tester);
    expect(find.text('Run overview'), findsOneWidget);

    await tester.tap(find.text('Dashboard'));
    await settle(tester);
    expect(find.text('ASX Market'), findsOneWidget);
  });

  testWidgets('the stock detail has no bottom navigation on desktop', (
    tester,
  ) async {
    await launchDesktop(tester);

    // A dashboard row selects the security for the chart panel; the panel's
    // action is what opens the detail screen.
    await tester.tap(find.text('MRNA').first);
    await settle(tester);
    await tester.tap(find.text('Open details'));
    await settle(tester);
    expect(find.byType(StockDetailScreen), findsOneWidget);

    // A bottom bar spanning the whole window under a 900px column reads as a
    // stretched phone screen; the sections sit under the header instead.
    expect(find.byType(NavigationBar), findsNothing);
    for (final tab in ['Overview', 'Metrics', 'Windows', 'Links']) {
      expect(find.text(tab), findsOneWidget, reason: '$tab missing');
    }

    // They still switch the content.
    await tester.tap(find.text('Windows'));
    await settle(tester);
    expect(find.text('Coverage by window'), findsOneWidget);
  });

  testWidgets('the desktop dashboard carries its own info button', (
    tester,
  ) async {
    await launchDesktop(tester);

    // The desktop dashboard draws its own top bar rather than an app bar, so
    // it would otherwise be the one section with no way to open its help.
    await tester.tap(find.byType(InfoButton));
    await settle(tester);
    expect(find.byType(InfoDialog), findsOneWidget);
    expect(find.text('Market cards'), findsOneWidget);
  });

  testWidgets('Reports shows the run metadata and the screen funnel', (
    tester,
  ) async {
    await launchDesktop(tester);

    await tester.tap(find.text('Reports'));
    await settle(tester);

    // The ASX fixture publishes both tables.
    expect(find.text('Run metadata'), findsOneWidget);
    expect(find.text('success'), findsOneWidget);
    expect(
      find.text('403'),
      findsNothing,
      reason: 'shown as screened of total',
    );
    expect(find.text('402 screened of 403'), findsOneWidget);
    expect(find.text('yahoo_finance'), findsOneWidget);
    expect(find.text('20260823T090042Z-30ac6f5b'), findsWidgets);
    expect(find.text('2.0'), findsOneWidget, reason: 'the price floor setting');

    expect(find.text('Screen funnel'), findsOneWidget);
    expect(find.text('Universe in window'), findsOneWidget);
    expect(find.text('Return above 10.0%'), findsOneWidget);
    // The 7D funnel first, with the drop from the stage above it.
    expect(find.text('6'), findsWidgets);
    expect(find.text('−204'), findsOneWidget);

    // Switching the window redraws the funnel from the same table.
    await tester.tap(
      find.descendant(
        of: find.byType(PeriodSelector<GrowthWindow>),
        matching: find.text('1M'),
      ),
    );
    await settle(tester);
    expect(find.text('16'), findsWidgets);

    // The US fixture publishes neither, and says so rather than showing a gap.
    // Its section sits below the ASX one, so scroll it into view first.
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await settle(tester);
    expect(find.textContaining('publishes no run metadata'), findsOneWidget);
  });

  testWidgets('the top bar search opens Markets filtered', (tester) async {
    await launchDesktop(tester);

    await tester.enterText(find.byType(TextField).first, 'AMLX');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);

    expect(find.text('AMLX'), findsWidgets);
    expect(find.text('MRNA'), findsNothing);
  });

  testWidgets('clicking a row charts that security', (tester) async {
    await launchDesktop(tester);

    // Defaults to the strongest mover.
    expect(find.textContaining('MRNA · Moderna'), findsOneWidget);

    await tester.tap(find.text('Amylyx Pharmaceuticals, Inc.').first);
    await settle(tester);

    expect(find.textContaining('AMLX · Amylyx'), findsOneWidget);
    // Selecting charts in place rather than navigating away.
    expect(find.text('ASX Market'), findsOneWidget);
  });

  testWidgets('the window dropdown drives the dashboard', (tester) async {
    await launchDesktop(tester);
    expect(find.text('Top Gainers (7 Day)'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<GrowthWindow>).first);
    await settle(tester);
    await tester.tap(find.text('1M').last);
    await settle(tester);

    expect(find.text('Top Gainers (1 Month)'), findsOneWidget);
  });
}
