import 'package:flutter/material.dart';

/// Colours the design uses that Material's scheme has no slot for.
@immutable
class ScreenerColors extends ThemeExtension<ScreenerColors> {
  const ScreenerColors({
    required this.positive,
    required this.positiveSurface,
    required this.negative,
    required this.negativeSurface,
    required this.neutral,
    required this.neutralSurface,
    required this.warning,
    required this.warningSurface,
    required this.card,
    required this.cardBorder,
    required this.pageBackground,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.chartGrid,
  });

  final Color positive;
  final Color positiveSurface;
  final Color negative;
  final Color negativeSurface;
  final Color neutral;
  final Color neutralSurface;
  final Color warning;
  final Color warningSurface;
  final Color card;
  final Color cardBorder;
  final Color pageBackground;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color chartGrid;

  /// Colour for a percentage/price delta.
  Color forChange(double value) => value >= 0 ? positive : negative;

  /// Background for a delta chip.
  Color surfaceForChange(double value) =>
      value >= 0 ? positiveSurface : negativeSurface;

  static const light = ScreenerColors(
    positive: Color(0xFF00875A),
    positiveSurface: Color(0xFFE3F6EC),
    negative: Color(0xFFC62828),
    negativeSurface: Color(0xFFFCEBEB),
    neutral: Color(0xFF5B6470),
    neutralSurface: Color(0xFFEFF1F4),
    warning: Color(0xFF96660C),
    warningSurface: Color(0xFFFBF0DC),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE7E9EE),
    pageBackground: Color(0xFFF4F6F8),
    textPrimary: Color(0xFF14181F),
    textSecondary: Color(0xFF616B77),
    textTertiary: Color(0xFF8C95A1),
    divider: Color(0xFFEDEFF3),
    chartGrid: Color(0xFFEDEFF3),
  );

  static const dark = ScreenerColors(
    positive: Color(0xFF4ADE9B),
    positiveSurface: Color(0xFF10352A),
    negative: Color(0xFFF87171),
    negativeSurface: Color(0xFF3A1B1B),
    neutral: Color(0xFF9AA4B2),
    neutralSurface: Color(0xFF232830),
    warning: Color(0xFFE9B44C),
    warningSurface: Color(0xFF33280F),
    card: Color(0xFF181C22),
    cardBorder: Color(0xFF272D36),
    pageBackground: Color(0xFF0F1216),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFFA5AEBA),
    textTertiary: Color(0xFF7A8494),
    divider: Color(0xFF242A33),
    chartGrid: Color(0xFF242A33),
  );

  @override
  ScreenerColors copyWith({
    Color? positive,
    Color? positiveSurface,
    Color? negative,
    Color? negativeSurface,
    Color? neutral,
    Color? neutralSurface,
    Color? warning,
    Color? warningSurface,
    Color? card,
    Color? cardBorder,
    Color? pageBackground,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? chartGrid,
  }) {
    return ScreenerColors(
      positive: positive ?? this.positive,
      positiveSurface: positiveSurface ?? this.positiveSurface,
      negative: negative ?? this.negative,
      negativeSurface: negativeSurface ?? this.negativeSurface,
      neutral: neutral ?? this.neutral,
      neutralSurface: neutralSurface ?? this.neutralSurface,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      pageBackground: pageBackground ?? this.pageBackground,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
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
      positive: mix(positive, other.positive),
      positiveSurface: mix(positiveSurface, other.positiveSurface),
      negative: mix(negative, other.negative),
      negativeSurface: mix(negativeSurface, other.negativeSurface),
      neutral: mix(neutral, other.neutral),
      neutralSurface: mix(neutralSurface, other.neutralSurface),
      warning: mix(warning, other.warning),
      warningSurface: mix(warningSurface, other.warningSurface),
      card: mix(card, other.card),
      cardBorder: mix(cardBorder, other.cardBorder),
      pageBackground: mix(pageBackground, other.pageBackground),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
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

  static const _seed = Color(0xFF00875A);
  static const _radius = 14.0;

  static ThemeData light() => _build(Brightness.light, ScreenerColors.light);

  static ThemeData dark() => _build(Brightness.dark, ScreenerColors.dark);

  static ThemeData _build(Brightness brightness, ScreenerColors colors) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    ).copyWith(surface: colors.pageBackground);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.pageBackground,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      extensions: [colors],
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
        labelColor: colors.positive,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.positive,
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
                ? colors.positive
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
                ? colors.positive
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
          borderSide: BorderSide(color: colors.positive, width: 1.4),
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
        color: colors.positive,
        linearTrackColor: colors.neutralSurface,
      ),
    );
  }
}
