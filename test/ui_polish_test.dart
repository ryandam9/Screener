import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/ui/screens/stock_detail_screen.dart';
import 'package:screener/ui/widgets/panels.dart';
import 'package:screener/ui/widgets/screen_reason.dart';
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

    for (final tab in ['Markets', 'Watchlist', 'More']) {
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

    final sheet = find.descendant(
      of: find.byType(InfoDialog),
      matching: find.byType(Scrollable),
    );
    // Both sections are below the fold now that the sheet also explains the
    // screen cut-off, so each is scrolled to rather than assumed.
    final heading = find.text('Two changes, both correct');
    await tester.scrollUntilVisible(heading, 120, scrollable: sheet);
    await settle(tester, frames: 4);
    expect(heading, findsOneWidget);

    final example = find.textContaining('sampling, not an error');
    await tester.scrollUntilVisible(example, 120, scrollable: sheet);
    await settle(tester, frames: 4);
    expect(example, findsOneWidget);
  });

  testWidgets('selection lives on the screens that need it, not app-wide', (
    tester,
  ) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    // Nothing wraps the navigator. One SelectionArea spanning routes is what
    // crashes the framework when a route comes or goes under it
    // (flutter/flutter#117527, #125065, #152230), and a market list scrolling
    // 150 rows through it is the churn that sets it off.
    expect(find.byType(SelectionArea), findsNothing);
    expect(
      SelectionContainer.maybeOf(tester.element(find.text('MRNA').first)),
      isNull,
      reason: 'list rows are tapped, not copied',
    );

    // The detail screen is where the numbers are read closely, so it carries
    // its own.
    await tester.tap(find.text('MRNA').first);
    await settle(tester);
    expect(find.byType(SelectionArea), findsOneWidget);

    final name = find.text('Moderna, Inc. - Common Stock');
    expect(name, findsWidgets);
    expect(
      SelectionContainer.maybeOf(tester.element(name.first)),
      isNotNull,
      reason: 'the detail text must sit inside the screen\'s selection area',
    );
  });

  testWidgets('an info sheet can be selected and quoted', (tester) async {
    await launchApp(tester, cacheDir: cacheDir, payloads: payloads);

    await tester.tap(find.byType(InfoButton));
    await settle(tester);

    final heading = find.text('Market cards');
    expect(
      SelectionContainer.maybeOf(tester.element(heading)),
      isNotNull,
      reason: 'the sheets explain the data and get quoted',
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

  group('the screen cut-off on screen', () {
    testWidgets('the detail screen says why the ticker is listed', (
      tester,
    ) async {
      await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
      await tester.tap(find.text('MRNA').first);
      await settle(tester);

      expect(find.byType(ScreenReason), findsOneWidget);
      expect(find.text('Why it is listed'), findsOneWidget);
      expect(
        find.textContaining('past the 10.0% cut-off'),
        findsOneWidget,
        reason: 'the rule the row satisfied should be named',
      );

      // The margin is the part that says how comfortably it cleared, in
      // percentage points rather than percent.
      expect(find.textContaining('by 107.9 points'), findsOneWidget);
    });

    testWidgets('a longer window states its own, higher cut-off', (
      tester,
    ) async {
      await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
      await tester.tap(find.text('MRNA').first);
      await settle(tester);

      await tester.tap(find.text('1Y'));
      await settle(tester);

      // A single app-wide number would be wrong: the published files screen
      // the year at 25%, not 10%.
      expect(find.textContaining('past the 25.0% cut-off'), findsOneWidget);
    });

    testWidgets('the metrics tab carries the cut-off and the margin', (
      tester,
    ) async {
      await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
      await tester.tap(find.text('MRNA').first);
      await settle(tester);
      await tester.tap(find.text('Metrics'));
      await settle(tester);

      await tester.scrollUntilVisible(find.text('Screen cut-off'), 200);
      await settle(tester, frames: 4);
      expect(find.text('10.0%'), findsWidgets);
      expect(find.text('Margin over cut-off'), findsOneWidget);
      expect(find.text('+107.9%'), findsWidgets);
    });

    testWidgets('the performance tab lists the cut-off per window', (
      tester,
    ) async {
      await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
      await tester.tap(find.text('MRNA').first);
      await settle(tester);
      await tester.tap(find.text('Performance'));
      await settle(tester);

      expect(find.text('Cut-off'), findsOneWidget);
      // 7D and 1M screen at 10%, the year at 25%.
      expect(find.text('10.0%'), findsWidgets);
      expect(find.text('25.0%'), findsOneWidget);
    });

    testWidgets('the list footer names the cut-off beside the count', (
      tester,
    ) async {
      await launchApp(tester, cacheDir: cacheDir, payloads: payloads);
      await tester.tap(find.text('Markets').last);
      await settle(tester);

      expect(find.textContaining('cut-off 10.0%'), findsOneWidget);
    });
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
