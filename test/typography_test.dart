import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screener/ui/desktop/widgets/desktop_cards.dart';
import 'package:screener/ui/widgets/panels.dart';
import 'package:screener/theme/app_theme.dart';

/// The typeface is the mockups' Roboto Condensed, and it is really bundled.
///
/// A family name the pubspec does not declare is not an error in Flutter: the
/// text quietly falls back to the platform default, which is exactly the
/// "colours changed, nothing else did" result the redesign was meant to fix.
void main() {
  test('the app font is Roboto Condensed and ships at every weight used', () {
    expect(kFontFamily, 'Roboto Condensed');
    expect(AppTheme.light().textTheme.bodyMedium?.fontFamily, kFontFamily);
    expect(AppTheme.dark().textTheme.titleLarge?.fontFamily, kFontFamily);

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- family: $kFontFamily'));
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final asset = 'assets/fonts/RobotoCondensed-$weight.ttf';
      expect(pubspec, contains(asset));
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
  });

  // A button's textStyle replaces the theme's rather than merging with it, so
  // one that sets only a size draws its label in the platform's default face.
  testWidgets('panel action buttons keep the app font', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              SectionHeader(
                title: 'Section',
                actionLabel: 'See all',
                onAction: () {},
              ),
              DesktopPanel(
                title: 'Panel',
                actionLabel: 'View all',
                onAction: () {},
                child: const SizedBox(height: 10),
              ),
            ],
          ),
        ),
      ),
    );

    for (final label in ['See all', 'View all']) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      expect(paragraph.text.style?.fontFamily, kFontFamily, reason: label);
    }
  });
}
