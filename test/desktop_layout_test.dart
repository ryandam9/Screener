import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/models/growth_window.dart';
import 'package:screener/ui/desktop/desktop_shell.dart';
import 'package:screener/ui/widgets/info_dialog.dart';
import 'package:screener/ui/widgets/change_chip.dart';
import 'package:screener/ui/widgets/panels.dart';
import 'package:screener/ui/widgets/table_frame.dart';
import 'package:screener/models/market.dart';
import 'package:screener/ui/desktop/desktop_dashboard.dart';
import 'package:screener/ui/desktop/widgets/gainers_table.dart';
import 'package:screener/ui/screens/app_shell.dart';
import 'package:screener/ui/screens/home_shell.dart';
import 'package:screener/ui/screens/market_list_screen.dart';
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

  Future<SharedPreferences> launchDesktop(WidgetTester tester) => launchApp(
    tester,
    cacheDir: cacheDir,
    payloads: payloads,
    size: desktopSize,
    devicePixelRatio: 1.0,
  );

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

  testWidgets('the sidebar collapses to a rail and stays that way', (
    tester,
  ) async {
    final prefs = await launchDesktop(tester);

    final expandedContent = tester.getTopLeft(find.byType(DesktopDashboard));

    await tester.tap(find.text('Collapse'));
    await settle(tester);

    // The labels go; the sections stay, reachable by icon.
    expect(find.text('Collapse'), findsNothing);
    expect(find.text('Markets'), findsNothing);
    expect(find.byIcon(AppSection.markets.icon), findsOneWidget);

    // The content starts further left than it did — that is the point.
    final content = tester.getTopLeft(find.byType(DesktopDashboard));
    expect(content.dx, lessThan(expandedContent.dx));
    expect(prefs.getBool('sidebar_collapsed'), isTrue);

    // And it is still navigable.
    await tester.tap(find.byIcon(AppSection.markets.icon));
    await settle(tester);
    expect(find.byType(MarketListScreen), findsOneWidget);
  });

  testWidgets('the sidebar lays out on every frame of both animations', (
    tester,
  ) async {
    await launchDesktop(tester);

    // Collapsing was covered; expanding was not, and it is the direction that
    // breaks: the flag flips on the first frame, while the sidebar is still
    // 68px wide and a label has nowhere to go. Overflows throw, so pumping
    // the animation frame by frame is the assertion.
    for (final _ in [1, 2]) {
      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left));
      for (var frame = 0; frame < 14; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await settle(tester, frames: 6);
    }

    // Back where it started, and still usable.
    expect(find.text('Collapse'), findsOneWidget);
    await tester.tap(find.text('Markets'));
    await settle(tester);
    expect(find.byType(MarketListScreen), findsOneWidget);
  });

  testWidgets('ctrl+B toggles the sidebar', (tester) async {
    final prefs = await launchDesktop(tester);
    expect(find.text('Collapse'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(find.text('Collapse'), findsNothing);
    expect(prefs.getBool('sidebar_collapsed'), isTrue);
  });

  testWidgets('the top bar names the section and hands it the width', (
    tester,
  ) async {
    await launchDesktop(tester);

    // The bar used to be one cluster of controls centred over an empty strip.
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('US and ASX growth screens'), findsOneWidget);

    final field = find.byType(TextField).first;
    final box = tester.getRect(field);
    expect(
      box.width,
      greaterThan(400),
      reason: 'the search box takes the width the bar was wasting',
    );
    expect(
      box.left,
      lessThan(desktopSize.width / 2),
      reason: 'it starts beside the title rather than floating in the middle',
    );
    // The controls that act on the page stay pinned to the right of it.
    expect(tester.getRect(find.text('Refresh')).left, greaterThan(box.right));
  });

  testWidgets('ctrl+F puts the caret in the search box from any section', (
    tester,
  ) async {
    await launchDesktop(tester);
    await tester.tap(find.text('Markets').last);
    await settle(tester);
    expect(find.byType(DesktopDashboard), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);

    expect(find.byType(DesktopDashboard), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('the gainers table can be filtered to one market', (
    tester,
  ) async {
    await launchDesktop(tester);

    final table = find.byType(GainersTable);
    expect(find.descendant(of: table, matching: find.text('MRNA')), findsOne);

    // Both markets are ranked together by default, so the stronger screen can
    // fill the table on its own; the filter is how the other one is seen.
    final filter = find.byType(PeriodSelector<Market?>);
    await tester.tap(find.descendant(of: filter, matching: find.text('ASX')));
    await settle(tester);

    expect(find.descendant(of: table, matching: find.text('QETH')), findsOne);
    expect(find.descendant(of: table, matching: find.text('MRNA')), findsNothing);

    // And the chart under the table follows the rows that are left.
    expect(find.textContaining('QETH ·'), findsOneWidget);
  });

  testWidgets('a row opens beside the list, not over it', (tester) async {
    await launchDesktop(tester);
    await tester.tap(find.text('Markets'));
    await settle(tester);

    // Nothing selected yet.
    expect(find.text('Select an instrument'), findsOneWidget);
    expect(find.byType(TableFrame), findsOneWidget, reason: 'framed list');

    await tester.tap(find.text('MRNA').first);
    await settle(tester);

    // The list is still there — the detail did not replace it.
    expect(find.byType(StockDetailScreen), findsOneWidget);
    expect(find.byType(MarketListScreen), findsOneWidget);
    expect(find.text('Select an instrument'), findsNothing);
    final list = tester.getTopLeft(find.byType(MarketListScreen));
    final detail = tester.getTopLeft(find.byType(StockDetailScreen));
    expect(
      detail.dx,
      greaterThan(list.dx),
      reason: 'the detail belongs beside the list, not over it',
    );

    // The pane fills what the list leaves: a Flexible list clamped to a
    // maximum used to keep its whole flex allocation and strand the excess as
    // a strip of background down the right of the window.
    final pane = tester.getRect(find.byType(StockDetailScreen));
    expect(
      desktopSize.width - pane.right,
      lessThan(28),
      reason: 'no wasted strip beside the detail',
    );

    // Closing the pane returns to the placeholder, list untouched.
    await tester.tap(find.byIcon(Icons.close));
    await settle(tester);
    expect(find.byType(StockDetailScreen), findsNothing);
    expect(find.text('Select an instrument'), findsOneWidget);
  });

  testWidgets('the handset list is not framed', (tester) async {
    await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
      size: const Size(1080, 2340),
    );
    await tester.tap(find.text('Markets').last);
    await settle(tester);

    // A border on every edge of a full-width list is noise, not structure.
    expect(find.byType(TableFrame), findsNothing);
  });

  /// The headings and the first row's values must end at the same edge.
  ///
  /// Each heading is looked at in a state where it carries no sort arrow, so
  /// the comparison is text edge against value edge.
  Future<void> checkHeadingsOverValues(WidgetTester tester) async {
    await tester.tap(find.text('Markets').last);
    await settle(tester);

    // Sorted by change to begin with, so "Price" is the heading without an
    // arrow: its right edge is the price column's right edge. A narrow phone
    // drops the price column from the rows, and the heading goes with it.
    final priced = find.text('Price').evaluate().isNotEmpty;
    if (priced) {
      expect(
        tester.getBottomRight(find.text('Price')).dx,
        closeTo(tester.getBottomRight(find.text('139.22').first).dx, 0.5),
        reason: '"Price" does not sit over the prices',
      );
      // Sort by price instead, which moves the arrow off "Change".
      await tester.tap(find.text('Price'));
    } else {
      expect(find.text('139.22'), findsNothing);
      // Ticker sorting is the other way to take the arrow off "Change".
      await tester.tap(find.text('Ticker'));
    }
    await settle(tester);
    expect(
      tester.getBottomRight(find.text('Change')).dx,
      closeTo(
        tester.getBottomRight(find.byType(ChangeChip).first).dx,
        0.5,
      ),
      reason: '"Change" does not sit over the change chips',
    );
  }

  testWidgets('the column headings sit over their values on desktop', (
    tester,
  ) async {
    await launchDesktop(tester);
    await checkHeadingsOverValues(tester);
  });

  testWidgets('the column headings sit over their values on a handset', (
    tester,
  ) async {
    await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
      size: handsetSize,
    );
    await checkHeadingsOverValues(tester);
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

  testWidgets('the one-column sections are framed and fill the window', (
    tester,
  ) async {
    await launchDesktop(tester);

    for (final section in ['Settings', 'Analysis', 'Reports']) {
      await tester.tap(find.text(section).first);
      await settle(tester);

      final frame = find.byType(PageFrame);
      expect(
        frame,
        findsOneWidget,
        reason: '$section floats on the window with no edge',
      );

      // Framed content, not a column of cards stranded in the middle: the
      // pane takes the width the window can give it.
      final width = tester.getSize(frame).width;
      expect(
        width,
        greaterThan(1000),
        reason: '$section is using ${width.toStringAsFixed(0)}px of 1440',
      );
    }
  });

  testWidgets('settings deal into three columns on a wide window', (
    tester,
  ) async {
    await launchDesktop(tester);
    await tester.tap(find.text('Settings').first);
    await settle(tester);

    // Sections are dealt round-robin, so the first three headings share a row
    // and the fourth starts the next one under the first.
    final dataSources = tester.getTopLeft(find.text('Data sources'));
    final appearance = tester.getTopLeft(find.text('Appearance'));
    final reports = tester.getTopLeft(find.text('Reports').last);
    final watchlist = tester.getTopLeft(find.text('Watchlist').last);

    expect(appearance.dx, greaterThan(dataSources.dx));
    expect(reports.dx, greaterThan(appearance.dx));
    expect((appearance.dy - dataSources.dy).abs(), lessThan(1));
    expect((reports.dy - dataSources.dy).abs(), lessThan(1));
    expect(watchlist.dx, dataSources.dx, reason: 'the fourth wraps around');
    expect(watchlist.dy, greaterThan(dataSources.dy));
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
