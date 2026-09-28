import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// The app's typeface, bundled in `assets/fonts` at weights 400/500/600/700.
///
/// Widgets inherit it through the theme; the chart painters do not (a
/// `TextPainter` has no ancestor to inherit from), so they name it explicitly.
const String kFontFamily = 'Inter';

/// Shared shape tokens for the app's panels and controls.
///
/// Keeping these outside [AppTheme] lets custom `Material` panels use the
/// same geometry as themed cards instead of repeating almost-identical
/// hard-coded radii.
///
/// Both are zero: the design has no rounded surfaces. They stay as named
/// tokens rather than being deleted so the handful of places that ask for a
/// radius keep reading as "the panel shape" instead of a bare literal, and so
/// softening the whole app again is a two-line change.
class AppRadii {
  const AppRadii._();

  static const double panel = 0;
  static const double control = 0;
}

/// The poster language's geometry.
///
/// Three numbers carry the whole look: how thick the ink outline is, how far
/// the solid shadow sits behind a surface, and the thinner outline used on
/// small blocks where the full weight would swamp the label inside. Every
/// surface reads them, so the app's heft is tuned here rather than in fifty
/// `Border.all` calls.
class AppBrut {
  const AppBrut._();

  /// Outline on a panel, card or row.
  static const double border = 2.5;

  /// Outline on a tag, chip or delta block.
  static const double hairline = 1.5;

  /// How far a surface's solid shadow sits down and to the right — and, since
  /// a press slides the surface into it, how far a tap moves it.
  static const double offset = 5;
}

/// Motion tokens for interaction, content replacement and navigation.
///
/// Package transitions and implicit animations share these durations. System
/// reduced-motion preferences turn them into immediate state changes.
class AppMotion {
  const AppMotion._();

  static const Duration selection = Duration(milliseconds: 160);
  static const Duration content = Duration(milliseconds: 220);
  static const Duration navigation = Duration(milliseconds: 240);

  static Duration forMedia(MediaQueryData media, Duration duration) =>
      media.disableAnimations ? Duration.zero : duration;

  static Duration selectionDuration(BuildContext context) =>
      forMedia(MediaQuery.of(context), selection);

  static Duration contentDuration(BuildContext context) =>
      forMedia(MediaQuery.of(context), content);
}

/// Colours the design uses that Material's scheme has no slot for.
@immutable
class ScreenerColors extends ThemeExtension<ScreenerColors> {
  const ScreenerColors({
    required this.interactive,
    required this.interactiveSurface,
    required this.positive,
    required this.positiveSurface,
    required this.negative,
    required this.negativeSurface,
    required this.neutral,
    required this.neutralSurface,
    required this.warning,
    required this.warningSurface,
    required this.starredSurface,
    required this.ink,
    required this.onAccent,
    required this.onInteractive,
    required this.card,
    required this.cardBorder,
    required this.pageBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.textName,
    required this.textTertiary,
    required this.divider,
    required this.chartGrid,
  });

  /// Selection, focus, navigation and primary actions.
  ///
  /// Deliberately not [positive]. When one colour says both "this is the page
  /// you are on" and "this instrument went up", a green sidebar item reads as
  /// a gain and a green focus ring reads as a status.
  final Color interactive;
  final Color interactiveSurface;

  final Color positive;
  final Color positiveSurface;
  final Color negative;
  final Color negativeSurface;
  final Color neutral;
  final Color neutralSurface;
  final Color warning;
  final Color warningSurface;

  /// Background of a list row whose ticker is on the watchlist.
  ///
  /// A wash rather than a tint: it sits under every row of a starred ticker in
  /// every list, so it has to be readable behind a whole row of text and still
  /// disappear when you are not looking for it. Warm, to belong to the same
  /// family as the star that put it there — [warningSurface] itself is spoken
  /// for by stale-data banners and is too strong to repeat down a list.
  final Color starredSurface;

  /// Every outline in the app, and the rule under every heading.
  ///
  /// Near-black on paper and near-white in the dark theme: the outline is the
  /// design, so it inverts with the page rather than fading into it the way a
  /// hairline card border used to.
  final Color ink;

  /// Text and outlines sitting on top of a saturated fill — a lime gain block,
  /// an amber warning, a coral loss.
  ///
  /// Near-black in *both* themes, because the fills themselves do not invert:
  /// lime is lime at midnight, and white text on lime is unreadable either way.
  final Color onAccent;

  /// Text sitting on [interactive]. Its own role because the violet is dark in
  /// the light theme and light in the dark one, so what reads on it flips.
  final Color onInteractive;

  final Color card;
  final Color cardBorder;
  final Color pageBackground;
  final Color textPrimary;
  final Color textSecondary;

  /// The security's name, wherever a ticker is listed.
  ///
  /// Its own role rather than [textSecondary]: a name is content — often the
  /// only way to tell what a four-letter ticker is — while most secondary text
  /// is chrome (labels, stamps, counts) that is meant to recede. At the sizes
  /// the lists use, secondary grey read as washed out, so this sits much
  /// closer to [textPrimary] and the name is set one weight up.
  final Color textName;

  final Color textTertiary;
  final Color divider;
  final Color chartGrid;

  /// Colour for a percentage/price delta.
  Color forChange(double value) => value >= 0 ? positive : negative;

  /// Background for a delta chip.
  Color surfaceForChange(double value) =>
      value >= 0 ? positiveSurface : negativeSurface;

  /// Ink on paper, with four saturated fills doing the signalling.
  ///
  /// Gains and losses are no longer coloured *text* — they are blocks of lime
  /// and coral with near-black type on them, which is both louder and a far
  /// better contrast ratio than the green-on-white it replaces.
  static const light = ScreenerColors(
    interactive: Color(0xFF6D4AFF),
    interactiveSurface: Color(0xFFE9E3FF),
    positive: Color(0xFF15803D),
    positiveSurface: Color(0xFFC6F432),
    negative: Color(0xFFBE2D14),
    negativeSurface: Color(0xFFFF6B4A),
    neutral: Color(0xFF3F3F3A),
    neutralSurface: Color(0xFFEAE6D9),
    warning: Color(0xFF7A4F00),
    warningSurface: Color(0xFFFFD23F),
    starredSurface: Color(0xFFFFF3C4),
    ink: Color(0xFF0B0B0B),
    onAccent: Color(0xFF0B0B0B),
    onInteractive: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFF0B0B0B),
    pageBackground: Color(0xFFF5F1E6),
    textPrimary: Color(0xFF0B0B0B),
    textSecondary: Color(0xFF4A4A42),
    textName: Color(0xFF1C1C18),
    textTertiary: Color(0xFF5A5A51),
    divider: Color(0xFF0B0B0B),
    chartGrid: Color(0xFFD8D3C4),
  );

  /// The same poster, printed white-on-black.
  ///
  /// The outline inverts with the page; the fills do not, because a lime that
  /// dimmed at night would stop being the point.
  static const dark = ScreenerColors(
    interactive: Color(0xFFA78BFA),
    interactiveSurface: Color(0xFF241B4D),
    positive: Color(0xFF9BE04A),
    positiveSurface: Color(0xFFC6F432),
    negative: Color(0xFFFF8A6B),
    negativeSurface: Color(0xFFFF6B4A),
    neutral: Color(0xFFBDB8A8),
    neutralSurface: Color(0xFF262626),
    warning: Color(0xFFF2C14E),
    warningSurface: Color(0xFFFFD23F),
    starredSurface: Color(0xFF2A2410),
    ink: Color(0xFFEDE9DC),
    onAccent: Color(0xFF0B0B0B),
    onInteractive: Color(0xFF0B0B0B),
    card: Color(0xFF1A1A1A),
    cardBorder: Color(0xFFEDE9DC),
    pageBackground: Color(0xFF101010),
    textPrimary: Color(0xFFF5F1E6),
    textSecondary: Color(0xFFBDB8A8),
    textName: Color(0xFFE2DDCC),
    textTertiary: Color(0xFFA8A396),
    divider: Color(0xFFEDE9DC),
    chartGrid: Color(0xFF3A3A36),
  );

  @override
  ScreenerColors copyWith({
    Color? interactive,
    Color? interactiveSurface,
    Color? positive,
    Color? positiveSurface,
    Color? negative,
    Color? negativeSurface,
    Color? neutral,
    Color? neutralSurface,
    Color? warning,
    Color? warningSurface,
    Color? starredSurface,
    Color? ink,
    Color? onAccent,
    Color? onInteractive,
    Color? card,
    Color? cardBorder,
    Color? pageBackground,
    Color? textPrimary,
    Color? textSecondary,
    Color? textName,
    Color? textTertiary,
    Color? divider,
    Color? chartGrid,
  }) {
    return ScreenerColors(
      interactive: interactive ?? this.interactive,
      interactiveSurface: interactiveSurface ?? this.interactiveSurface,
      positive: positive ?? this.positive,
      positiveSurface: positiveSurface ?? this.positiveSurface,
      negative: negative ?? this.negative,
      negativeSurface: negativeSurface ?? this.negativeSurface,
      neutral: neutral ?? this.neutral,
      neutralSurface: neutralSurface ?? this.neutralSurface,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      starredSurface: starredSurface ?? this.starredSurface,
      ink: ink ?? this.ink,
      onAccent: onAccent ?? this.onAccent,
      onInteractive: onInteractive ?? this.onInteractive,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      pageBackground: pageBackground ?? this.pageBackground,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textName: textName ?? this.textName,
      textTertiary: textTertiary ?? this.textTertiary,
      divider: divider ?? this.divider,
      chartGrid: chartGrid ?? this.chartGrid,
    );
  }

  @override
  ScreenerColors lerp(ThemeExtension<ScreenerColors>? other, double t) {
    if (other is! ScreenerColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ScreenerColors(
      interactive: mix(interactive, other.interactive),
      interactiveSurface: mix(interactiveSurface, other.interactiveSurface),
      positive: mix(positive, other.positive),
      positiveSurface: mix(positiveSurface, other.positiveSurface),
      negative: mix(negative, other.negative),
      negativeSurface: mix(negativeSurface, other.negativeSurface),
      neutral: mix(neutral, other.neutral),
      neutralSurface: mix(neutralSurface, other.neutralSurface),
      warning: mix(warning, other.warning),
      warningSurface: mix(warningSurface, other.warningSurface),
      starredSurface: mix(starredSurface, other.starredSurface),
      ink: mix(ink, other.ink),
      onAccent: mix(onAccent, other.onAccent),
      onInteractive: mix(onInteractive, other.onInteractive),
      card: mix(card, other.card),
      cardBorder: mix(cardBorder, other.cardBorder),
      pageBackground: mix(pageBackground, other.pageBackground),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textName: mix(textName, other.textName),
      textTertiary: mix(textTertiary, other.textTertiary),
      divider: mix(divider, other.divider),
      chartGrid: mix(chartGrid, other.chartGrid),
    );
  }
}

/// Convenience accessor: `context.colors.positive`.
extension ScreenerColorsX on BuildContext {
  ScreenerColors get colors => Theme.of(this).extension<ScreenerColors>()!;
}

class AppTheme {
  const AppTheme._();

  /// Material derives focus rings, ripples and text selection from this, so
  /// it follows the interactive colour rather than the gain colour.
  static const _seed = Color(0xFF6D4AFF);

  static ThemeData light() => _build(Brightness.light, ScreenerColors.light);

  static ThemeData dark() => _build(Brightness.dark, ScreenerColors.dark);

  static ThemeData _build(Brightness brightness, ScreenerColors colors) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    ).copyWith(surface: colors.pageBackground);

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: kFontFamily,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.pageBackground,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      extensions: [colors],
      // Pushed routes slide and fade along the horizontal axis on every
      // platform, so a drill-down reads the same on a handset and a desktop.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const SharedAxisPageTransitionsBuilder(
              transitionType: SharedAxisTransitionType.horizontal,
              fillColor: Colors.transparent,
            ),
        },
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: colors.textPrimary,
            displayColor: colors.textPrimary,
          )
          .copyWith(
            headlineLarge: base.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: colors.textPrimary,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: colors.textPrimary,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
            labelSmall: base.textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
      // The bar sits on the page rather than on its own white plane, so the
      // masthead below it reads as the top of one poster instead of a title
      // bar with content under it. The rule is drawn by the screen.
      appBarTheme: AppBarTheme(
        backgroundColor: colors.pageBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.ink, width: AppBrut.border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        space: 1,
        thickness: 1.5,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.interactive,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.interactive,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: colors.divider,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? colors.interactive
                : colors.textTertiary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.4,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w900
                : FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? colors.interactive
                : colors.textTertiary,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.neutralSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.ink, width: AppBrut.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.ink, width: AppBrut.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: colors.interactive, width: 3),
        ),
        hintStyle: TextStyle(color: colors.textTertiary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.interactive,
        contentTextStyle: TextStyle(
          color: colors.onInteractive,
          fontWeight: FontWeight.w700,
        ),
        actionTextColor: colors.onInteractive,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.ink, width: AppBrut.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: colors.textSecondary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.interactive,
        linearTrackColor: colors.neutralSurface,
      ),
    );
  }
}
