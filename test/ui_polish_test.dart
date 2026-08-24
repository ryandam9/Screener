import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/ui/screens/stock_detail_screen.dart';
import 'package:screener/ui/widgets/panels.dart';
import 'package:screener/ui/widgets/info_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// The chrome around the data: info sheets, selectable text, and the settings
/// layout.
void main() {
  late Directory cacheDir;
  late Directory serveDir;
  late Map<String, List<int>> payloads;

  const desktopSize = Size(1440, 900);
  const handsetSize = Size(1080, 2340);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cacheDir = await Directory.systemTemp.createTemp('screener_polish_cache');
    serveDir = await Directory.systemTemp.createTemp('screener_polish_serve');
    payloads = await buildFixturePayloads(serveDir);
  });

  tearDown(() async {
    for (final dir in [cacheDir, serveDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  testWidgets('the info button explains the dashboard', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    await tester.tap(find.byType(InfoButton));
    await settle(tester);

    expect(find.byType(InfoDialog), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Market cards'), findsOneWidget);

    // Headings, bullets, worked examples and caveats all render; the sheet
    // scrolls, so the later blocks are scrolled to rather than assumed.
    final sheet = find.descendant(
      of: find.byType(InfoDialog),
      matching: find.byType(Scrollable),
    );
    for (final text in [
      find.textContaining('Median, not average', findRichText: true),
      find.text('Reading a row'),
      find.textContaining('not a live quote'),
    ]) {
      await tester.scrollUntilVisible(text, 120, scrollable: sheet);
      await settle(tester, frames: 4);
      expect(text, findsOneWidget);
    }

    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.byType(InfoDialog), findsNothing);
  });

  testWidgets('every screen with an app bar carries an info button', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    for (final tab in ['Markets', 'Watchlist', 'Analysis', 'More']) {
      await tester.tap(find.text(tab).last);
      await settle(tester);
      expect(
        find.byType(InfoButton),
        findsOneWidget,
        reason: '$tab has no info button',
      );
    }
  });

  testWidgets('the stock detail sheet explains the two changes', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    await tester.tap(find.text('MRNA').first);
    await settle(tester);
    expect(find.byType(StockDetailScreen), findsOneWidget);

    await tester.tap(find.byType(InfoButton));
    await settle(tester);
    expect(find.text('Two changes, both correct'), findsOneWidget);

    final example = find.textContaining('sampling, not an error');
    await tester.scrollUntilVisible(
      example,
      120,
      scrollable: find.descendant(
        of: find.byType(InfoDialog),
        matching: find.byType(Scrollable),
      ),
    );
    await settle(tester, frames: 4);
    expect(example, findsOneWidget);
  });

  testWidgets('body text is selectable', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    // One selection area covers the whole navigator, so any screen's text is
    // selectable without each screen opting in.
    expect(find.byType(SelectionArea), findsOneWidget);
    final ticker = tester.widget<Text>(find.text('MRNA').first);
    final selectable = SelectionContainer.maybeOf(
      tester.element(find.text('MRNA').first),
    );
    expect(ticker.data, 'MRNA');
    expect(
      selectable,
      isNotNull,
      reason: 'list text must sit inside the selection area',
    );
  });

  testWidgets('the charts opt out of selection so drags reach them', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    // SelectionContainer.disabled inserts a container that reports no content;
    // without it the app-wide SelectionArea would take the chart's drags.
    expect(
      find.descendant(
        of: find.byType(StockDetailScreen),
        matching: find.byType(SelectionContainer),
      ),
      findsWidgets,
    );
  });

  testWidgets('the stock detail keeps its bottom navigation on a handset', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('every period reads as a button, not only the selected one', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    final pills = find.descendant(
      of: find.byType(PeriodSelector<GrowthWindow>),
      matching: find.byType(AnimatedContainer),
    );
    expect(pills, findsWidgets);

    for (final pill in tester.widgetList<AnimatedContainer>(pills)) {
      final decoration = pill.decoration! as BoxDecoration;
      // An unselected period used to be bare text on the card, which gave no
      // clue that it could be clicked.
      expect(decoration.color, isNot(Colors.transparent));
      expect(decoration.border, isNotNull);
    }
  });

  testWidgets('settings sit in two columns on a wide window', (tester) async {
    await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
      size: desktopSize,
      devicePixelRatio: 1.0,
    );

    await tester.tap(find.text('Settings'));
    await settle(tester);

    final dataSources = tester.getTopLeft(find.text('Data sources'));
    final appearance = tester.getTopLeft(find.text('Appearance'));
    expect(
      appearance.dx,
      greaterThan(dataSources.dx),
      reason: 'the second section should start a second column',
    );
    expect(
      (appearance.dy - dataSources.dy).abs(),
      lessThan(1),
      reason: 'both columns should start at the same height',
    );
  });

  testWidgets('settings stack in one column on a handset', (tester) async {
    await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
      size: handsetSize,
    );

    await tester.tap(find.text('More'));
    await settle(tester);

    final dataSources = tester.getTopLeft(find.text('Data sources'));
    final appearance = tester.getTopLeft(find.text('Appearance'));
    expect(appearance.dx, dataSources.dx);
    expect(appearance.dy, greaterThan(dataSources.dy));
  });
}
