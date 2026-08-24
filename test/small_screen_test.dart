import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/ui/widgets/info_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/app_harness.dart';

/// A sweep of every screen at the widths and text sizes a phone actually uses.
///
/// Layout overflows throw during the paint that follows them, so a walk that
/// visits each screen, opens each sheet and scrolls each list is enough to
/// catch them — the assertion is that the walk completes without a single
/// exception. 320dp is the narrowest Android phone still in circulation; 1.3x
/// text is one notch below the largest accessibility setting most people use.
void main() {
  late Directory cacheDir;
  late Directory serveDir;
  late Map<String, List<int>> payloads;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cacheDir = await Directory.systemTemp.createTemp('screener_small_cache');
    serveDir = await Directory.systemTemp.createTemp('screener_small_serve');
    payloads = await buildFixturePayloads(serveDir);
  });

  tearDown(() async {
    for (final dir in [cacheDir, serveDir]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  /// Scrolls whatever is under [at] to the end and back, so every row gets
  /// built and laid out rather than only the first screenful.
  ///
  /// Dragging from a point rather than from a `Scrollable` finder: several
  /// screens nest scrollables, and the outer one is not always the one the
  /// finder picks.
  Future<void> sweep(WidgetTester tester, {Offset? at}) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final point = at ?? Offset(size.width / 2, size.height * 0.55);
    for (var i = 0; i < 4; i++) {
      await tester.dragFrom(point, const Offset(0, -320));
      await settle(tester, frames: 4);
    }
    await tester.dragFrom(point, const Offset(0, 2000));
    await settle(tester, frames: 4);

    // A drag that no scrollable claimed lands on the app-wide SelectionArea
    // and leaves a selection toolbar floating over the screen, which then
    // swallows the next tap. Clear it the way tapping elsewhere would.
    final region = find.byType(SelectableRegion);
    if (region.evaluate().isNotEmpty) {
      tester.state<SelectableRegionState>(region.first).clearSelection();
      await settle(tester, frames: 2);
    }
  }

  /// The detail screen draws its own back button rather than an app bar's.
  Future<void> goBack(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await settle(tester);
  }

  Future<void> openAndCloseInfo(WidgetTester tester) async {
    final button = find.byType(InfoButton);
    if (button.evaluate().isEmpty) return;
    await tester.tap(button.first);
    await settle(tester);
    await sweep(tester);
    await tester.tap(find.text('Close'));
    await settle(tester);
  }

  /// Walks the whole app once at whatever size the view is set to.
  Future<void> walk(WidgetTester tester) async {
    await launchApp(
      tester,
      cacheDir: cacheDir,
      payloads: payloads,
      size: tester.view.physicalSize,
      devicePixelRatio: tester.view.devicePixelRatio,
    );

    // Dashboard, including its info sheet and the market cards.
    await sweep(tester);
    await openAndCloseInfo(tester);

    // Markets: every tab, the search field, and both sheets.
    await tester.tap(find.text('Markets').last);
    await settle(tester);
    // The tab labels shorten under 360dp, so each is looked up either way.
    for (final tab in [
      ['Top Movers', 'Movers'],
      ['Consistent', 'Consistent'],
      ['Watchlist', 'Starred'],
      ['All Stocks', 'All'],
    ]) {
      final long = find.descendant(
        of: find.byType(TabBar),
        matching: find.text(tab.first),
      );
      await tester.tap(
        long.evaluate().isNotEmpty
            ? long
            : find.descendant(
                of: find.byType(TabBar),
                matching: find.text(tab.last),
              ),
      );
      await settle(tester);
      await sweep(tester);
    }
    await openAndCloseInfo(tester);

    // The market/window sheet hangs off the title.
    await tester.tap(find.byIcon(Icons.filter_list));
    await settle(tester);
    await sweep(tester);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);

    // A stock, its four tabs and every window.
    await tester.tap(find.text('MRNA').first);
    await settle(tester);
    for (final label in ['1M', '1Y', '7D']) {
      final pill = find.text(label);
      if (pill.evaluate().isNotEmpty) {
        await tester.tap(pill.first);
        await settle(tester);
      }
    }
    for (final tab in ['Metrics', 'Windows', 'Links', 'Overview']) {
      await tester.tap(find.text(tab));
      await settle(tester);
      await sweep(tester);
    }
    await openAndCloseInfo(tester);
    await goBack(tester);

    // The remaining tabs.
    for (final tab in ['Watchlist', 'Analysis', 'More']) {
      await tester.tap(find.text(tab).last);
      await settle(tester);
      await sweep(tester);
      await openAndCloseInfo(tester);
    }

    // Reports, reached from More — below the fold on a short screen.
    final reports = find.text('Runs and CSV export');
    await tester.scrollUntilVisible(reports, 200);
    await settle(tester, frames: 4);
    await tester.tap(reports);
    await settle(tester);
    await sweep(tester);
    await openAndCloseInfo(tester);
    await goBack(tester);
  }

  /// True when a Text finder's rendered paragraph had to cut its content.
  bool truncated(WidgetTester tester, Finder finder) {
    // Down to the paragraph itself: the app-wide SelectionArea puts a mouse
    // region between the Text and its render object.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: finder, matching: find.byType(RichText)).first,
    );
    return paragraph.didExceedMaxLines;
  }

  for (final (width, height, scale) in [
    (320.0, 640.0, 1.0),
    (360.0, 740.0, 1.0),
    (360.0, 740.0, 1.3),
  ]) {
    testWidgets(
      'company names are readable in full at ${width.toInt()}dp @${scale}x',
      (tester) async {
        tester.view.physicalSize = Size(width, height);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await launchApp(
          tester,
          cacheDir: cacheDir,
          payloads: payloads,
          size: tester.view.physicalSize,
          devicePixelRatio: 1.0,
        );

        await tester.tap(find.text('Markets').last);
        await settle(tester);

        // The longest name the fixture publishes. It used to render as
        // "Amylyx Pharmac…", which identifies nothing.
        const name = 'Amylyx Pharmaceuticals, Inc.';
        expect(find.text(name), findsWidgets);
        expect(
          truncated(tester, find.text(name).first),
          isFalse,
          reason: 'the name is still being cut short',
        );

        // And on the dashboard's gainers, which use the other tile.
        await tester.tap(find.text('Dashboard').last);
        await settle(tester);
        expect(
          truncated(tester, find.text(name).first),
          isFalse,
          reason: 'the dashboard tile cuts the name',
        );
      },
    );
  }

  for (final (width, height, scale) in [
    (320.0, 640.0, 1.0), // the narrowest phone still in use
    (360.0, 740.0, 1.0), // the most common Android size
    (412.0, 915.0, 1.0), // a large phone
    (360.0, 740.0, 1.3), // large text, where fixed heights break first
    (320.0, 640.0, 1.3), // both at once
    (320.0, 640.0, 1.6), // the largest text most phones offer
    (640.0, 320.0, 1.0), // landscape, where fixed heights run out of room
  ]) {
    testWidgets('lays out at ${width.toInt()}x${height.toInt()} @${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await walk(tester);
    });
  }
}
