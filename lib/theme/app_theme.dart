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
class AppRadii {
  const AppRadii._();

  static const double panel = 12;
  static const double control = 10;
}

class AppSpacing {
  const AppSpacing._();

  static const double mobilePage = 16;
  static const double desktopPage = 24;
  static const double panelGap = 18;
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

  static const light = ScreenerColors(
    // Deep teal keeps the product's original market identity. Positive values
    // lean greener and use their own surface, so selection and performance
    // remain distinguishable while both clear small-text contrast targets.
    interactive: Color(0xFF0F766E),
    interactiveSurface: Color(0xFFE6F4F1),
    positive: Color(0xFF11734F),
    positiveSurface: Color(0xFFE7F6EF),
    negative: Color(0xFFB83243),
    negativeSurface: Color(0xFFFCEBED),
    neutral: Color(0xFF596474),
    neutralSurface: Color(0xFFF0F2F5),
    warning: Color(0xFF9A6700),
    warningSurface: Color(0xFFFFF3D6),
    starredSurface: Color(0xFFFFF8E8),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE1E6EC),
    pageBackground: Color(0xFFF6F8FA),
    textPrimary: Color(0xFF17202B),
    textSecondary: Color(0xFF566273),
    textName: Color(0xFF344152),
    textTertiary: Color(0xFF667284),
    divider: Color(0xFFE8ECF1),
    chartGrid: Color(0xFFE8ECF1),
  );

  static const dark = ScreenerColors(
    interactive: Color(0xFF5EEAD4),
    interactiveSurface: Color(0xFF123630),
    positive: Color(0xFF65D6A6),
    positiveSurface: Color(0xFF12382D),
    negative: Color(0xFFFF7A86),
    negativeSurface: Color(0xFF3B1D23),
    neutral: Color(0xFFA4AFBD),
    neutralSurface: Color(0xFF232A33),
    warning: Color(0xFFF2C45D),
    warningSurface: Color(0xFF392E13),
    starredSurface: Color(0xFF2B2512),
    card: Color(0xFF171C23),
    cardBorder: Color(0xFF2B333E),
    pageBackground: Color(0xFF0E1319),
    textPrimary: Color(0xFFF4F7FA),
    textSecondary: Color(0xFFADB7C5),
    textName: Color(0xFFD0D7E2),
    textTertiary: Color(0xFF929EAE),
    divider: Color(0xFF252C35),
    chartGrid: Color(0xFF252C35),
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
  static const _seed = Color(0xFF0F766E);
  static const _radius = AppRadii.panel;

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
      appBarTheme: AppBarTheme(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: colors.cardBorder),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        space: 1,
        thickness: 1,
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
        indicatorColor: colors.interactiveSurface,
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
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
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
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.interactive, width: 1.4),
        ),
        hintStyle: TextStyle(color: colors.textTertiary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.textPrimary,
        contentTextStyle: TextStyle(color: colors.card),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: colors.textSecondary),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.interactive,
        linearTrackColor: colors.neutralSurface,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.interactive,
          foregroundColor: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF062A25),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.cardBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.interactive
                : colors.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.interactiveSurface
                : colors.card,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: colors.cardBorder)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
