import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// The app's typeface, bundled in `assets/fonts` at weights 400/500/600/700.
///
/// Widgets inherit it through the theme; the chart painters do not (a
/// `TextPainter` has no ancestor to inherit from), so they name it explicitly.
const String kFontFamily = 'Roboto Condensed';

/// How much larger than its nominal size every piece of text is drawn.
///
/// The sizes across the app were chosen for Inter. Roboto Condensed has
/// nearly the same letter height but is ~18% narrower, so at the same size
/// it read as small type. Applied once, on top of the reader's own text
/// scale, by [BoostedTextScaler]. Chart painters receive that same scaler
/// from MediaQuery so labels and tooltips follow the reader’s preferences.
const double kTypeScale = 1.15;

/// The reader's text scale, with [kTypeScale] applied before it.
///
/// Wraps rather than replaces, so a non-linear system scale (Android 14
/// grows small text more than large) keeps its shape.
@immutable
class BoostedTextScaler extends TextScaler {
  const BoostedTextScaler(this.inner);

  final TextScaler inner;

  @override
  double scale(double fontSize) => inner.scale(fontSize * kTypeScale);

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => inner.textScaleFactor * kTypeScale;

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) => BoostedTextScaler(
    inner.clamp(
      minScaleFactor: minScaleFactor / kTypeScale,
      maxScaleFactor: maxScaleFactor / kTypeScale,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is BoostedTextScaler && other.inner == inner;

  @override
  int get hashCode => Object.hash(BoostedTextScaler, inner);
}

/// Geometry shared by cards, tables, dialogs and controls.
class AppRadii {
  const AppRadii._();

  static const double panel = 12;
  static const double control = 8;
}

class AppBorders {
  const AppBorders._();

  static const double border = 1;
  static const double hairline = 1;
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

  /// Primary ink, including text on neutral badges.
  final Color ink;

  /// Text on semantic tinted surfaces.
  final Color onAccent;

  /// Text on the primary action fill.
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

  /// Semantic palette for the light workspace.
  static const light = ScreenerColors(
    interactive: Color(0xFF0F766E),
    interactiveSurface: Color(0xFFE5EEF9),
    positive: Color(0xFF137547),
    positiveSurface: Color(0xFFE7F5ED),
    negative: Color(0xFFB63342),
    negativeSurface: Color(0xFFFCECEF),
    neutral: Color(0xFF526075),
    neutralSurface: Color(0xFFEEF1F6),
    warning: Color(0xFF8A5B0A),
    warningSurface: Color(0xFFFFF3D9),
    starredSurface: Color(0xFFFFF9E9),
    ink: Color(0xFF172235),
    onAccent: Color(0xFF172235),
    onInteractive: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE0E5ED),
    pageBackground: Color(0xFFEDF2F7),
    textPrimary: Color(0xFF172235),
    textSecondary: Color(0xFF526075),
    textName: Color(0xFF29394F),
    textTertiary: Color(0xFF616E82),
    divider: Color(0xFFE5E9F0),
    chartGrid: Color(0xFFE5E9F0),
  );

  /// Semantic palette for the dark workspace.
  static const dark = ScreenerColors(
    interactive: Color(0xFF5ED3C4),
    interactiveSurface: Color(0xFF20344D),
    positive: Color(0xFF70D5A1),
    positiveSurface: Color(0xFF193B2D),
    negative: Color(0xFFFF9CA8),
    negativeSurface: Color(0xFF492731),
    neutral: Color(0xFFB4C0D2),
    neutralSurface: Color(0xFF253145),
    warning: Color(0xFFF1C66F),
    warningSurface: Color(0xFF44371F),
    starredSurface: Color(0xFF363225),
    ink: Color(0xFFEDF2FA),
    onAccent: Color(0xFFEDF2FA),
    onInteractive: Color(0xFF04231F),
    card: Color(0xFF192334),
    cardBorder: Color(0xFF334156),
    pageBackground: Color(0xFF111A28),
    textPrimary: Color(0xFFEDF2FA),
    textSecondary: Color(0xFFB4C0D2),
    textName: Color(0xFFDEE6F2),
    textTertiary: Color(0xFFA2B0C4),
    divider: Color(0xFF2D3A4D),
    chartGrid: Color(0xFF2D3A4D),
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
  static const _seed = Color(0xFF0F766E);

  static ThemeData light() => _build(Brightness.light, ScreenerColors.light);

  static ThemeData dark() => _build(Brightness.dark, ScreenerColors.dark);

  static ThemeData _build(Brightness brightness, ScreenerColors colors) {
    final scheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: brightness).copyWith(
          primary: colors.interactive,
          onPrimary: colors.onInteractive,
          primaryContainer: colors.interactiveSurface,
          onPrimaryContainer: colors.interactive,
          surface: colors.card,
          onSurface: colors.textPrimary,
          onSurfaceVariant: colors.textSecondary,
          outline: colors.cardBorder,
          outlineVariant: colors.divider,
          error: colors.negative,
          onError: brightness == Brightness.light
              ? Colors.white
              : colors.pageBackground,
        );

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
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: kFontFamily,
          color: colors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          side: BorderSide(color: colors.cardBorder, width: AppBorders.border),
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
        labelStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: kFontFamily,
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
            fontFamily: kFontFamily,
            fontSize: 11,
            letterSpacing: 0,
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
        fillColor: colors.pageBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: colors.cardBorder,
            width: AppBorders.border,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(
            color: colors.cardBorder,
            width: AppBorders.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colors.interactive, width: 2),
        ),
        hintStyle: TextStyle(
          fontFamily: kFontFamily,
          color: colors.textTertiary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.interactive,
        contentTextStyle: TextStyle(
          fontFamily: kFontFamily,
          color: colors.onInteractive,
          fontWeight: FontWeight.w700,
        ),
        actionTextColor: colors.onInteractive,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          side: BorderSide(color: colors.cardBorder, width: AppBorders.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        titleTextStyle: TextStyle(
          fontFamily: kFontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: kFontFamily,
          fontSize: 13,
          color: colors.textSecondary,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
          side: BorderSide(color: colors.cardBorder),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          side: BorderSide(color: colors.cardBorder),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          textStyle: const TextStyle(
            fontFamily: kFontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.interactive,
          side: BorderSide(color: colors.cardBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          // The app's selection tint, not the seed palette's: left to
          // Material, a selected segment came out green.
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.interactiveSurface
                : null,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.interactive
                : colors.textPrimary,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: colors.cardBorder)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.interactive,
        linearTrackColor: colors.neutralSurface,
      ),
    );
  }
}
