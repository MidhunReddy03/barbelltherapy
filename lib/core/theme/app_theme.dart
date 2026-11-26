import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Builds the app ThemeData for dark (default) and light themes, matching
/// the GymDesk App Screens design (Barlow Condensed + Inter + Noto Sans Telugu).
class AppTheme {
  AppTheme._();

  static const String teluguFallbackFamily = 'Noto Sans Telugu';

  /// Display font helper (.dsp from the HTML screens: Barlow Condensed, uppercase, 0.02em letter spacing).
  static TextStyle dsp({
    double fontSize = 24,
    FontWeight fontWeight = FontWeight.w600,
    Color color = AppColors.textPrimaryDark,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.barlowCondensed(
      textStyle: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing ?? (0.02 * fontSize),
        height: height ?? 1.05,
        fontFamilyFallback: const [teluguFallbackFamily],
      ),
    );
  }

  /// Caption overline helper (.cap from HTML screens: 11px uppercase, 0.08em letter spacing, semibold).
  static TextStyle cap({
    Color color = AppColors.textSecondaryDark,
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return GoogleFonts.inter(
      textStyle: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: 0.08 * fontSize,
        fontFamilyFallback: const [teluguFallbackFamily],
      ),
    );
  }

  /// Card decoration matching .card from the HTML screens:
  /// background: #1F2226; border: 1px solid #32373D; border-radius: 14px;
  static BoxDecoration cardDecoration({
    Color backgroundColor = AppColors.surfaceDark,
    Color borderColor = AppColors.borderDark,
    double radius = AppColors.radius,
    Border? border,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      border: border ?? Border.all(color: borderColor),
    );
  }

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final surfaceRaised =
        isDark ? AppColors.surfaceRaisedDark : AppColors.surfaceRaisedLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.accentHighlight,
      onSecondary: AppColors.onAccent,
      error: AppColors.statusExpired,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceRaised,
      onSurfaceVariant: textSecondary,
      outline: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(textPrimary, textSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: dsp(fontSize: 26, fontWeight: FontWeight.w700, color: textPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: _style(14, FontWeight.w500, textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 76,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accentHighlight,
            );
          }
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.accentHighlight, size: 24);
          }
          return IconThemeData(color: textSecondary, size: 24);
        }),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        hintStyle: TextStyle(fontSize: 14, color: textSecondary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.onAccent;
          }
          return textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.accent;
          return surfaceRaised;
        }),
      ),
    );
  }

  /// Typography scale from the spec: title 22/semibold, section 16/semibold,
  /// body 14, caption 12, dashboard numbers 28/bold.
  static TextTheme _textTheme(Color primary, Color secondary) {
    TextStyle make(double size, FontWeight weight, Color color) =>
        GoogleFonts.inter(
          textStyle: TextStyle(
            fontSize: size,
            fontWeight: weight,
            color: color,
            fontFamilyFallback: const [teluguFallbackFamily],
          ),
        );

    return TextTheme(
      displaySmall: dsp(fontSize: 32, fontWeight: FontWeight.w700, color: primary),
      titleLarge: dsp(fontSize: 24, fontWeight: FontWeight.w700, color: primary),
      titleMedium: make(16, FontWeight.w600, primary),
      bodyMedium: make(14, FontWeight.w400, primary),
      bodySmall: make(12, FontWeight.w400, secondary),
      labelLarge: make(14, FontWeight.w600, primary),
    );
  }

  static TextStyle _style(double size, FontWeight weight, Color color) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color);
}
