import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_spacing.dart'; // Import for spacing constants
import 'app_colors.dart'; // Import base colors
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'is_dark_mode';
  late SharedPreferences _prefs;
  ThemeMode _themeMode = ThemeMode.system;

  ThemeProvider() {
    _loadThemeMode();
  }

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      final brightness = SchedulerBinding.instance.window.platformBrightness;
      return brightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  // Note: AppSpacing constants should be accessed directly:
  // import '../theme/app_spacing.dart';
  // Then use: AppSpacing.blockSpacing, AppSpacing.headerSpacer, etc.

  // Enhanced gradients with more intermediate steps for smoother transitions
  static const _primaryGradient = [
    Color(0xFF7B61FF),
    Color(0xFF8269FF),
    Color(0xFF8971FF),
    Color(0xFF8F79FF),
    Color(0xFF9582FF),
    Color(0xFF9C8FFF),
  ];

  static const _secondaryGradient = [
    Color(0xFFFF6B6B),
    Color(0xFFFF7373),
    Color(0xFFFF7A7A),
    Color(0xFFFF8282),
    Color(0xFFFF8989),
    Color(0xFFFF8E8E),
  ];

  static const _accentGradient = [
    Color(0xFF48DAD0),
    Color(0xFF52DDD4),
    Color(0xFF5CE0D8),
    Color(0xFF66E3DC),
    Color(0xFF6EE6DE),
    Color(0xFF76E8E0),
  ];

  Future<void> _loadThemeMode() {
    // TODO: Load theme mode preference from storage
    // For now, defaults to system
    final brightness = SchedulerBinding.instance.window.platformBrightness;
    _themeMode =
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    return Future.value();
  }

  void toggleTheme(bool isOn) {
    _themeMode = isOn ? ThemeMode.dark : ThemeMode.light;
    // TODO: Persist theme mode preference (e.g., using shared_preferences)
    notifyListeners();
  }

  ThemeData get currentTheme => isDarkMode ? darkTheme : lightTheme;

  // Add getters for the themes
  ThemeData get lightTheme {
    final baseTheme = ThemeData.light(useMaterial3: true);
    return baseTheme.copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: Colors.deepPurple.shade300,
        foregroundColor: Colors.white,
        elevation: 4.0,
        toolbarHeight: 65.0, // Increased height for mobile friendliness
        titleTextStyle: GoogleFonts.roboto(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      textTheme: GoogleFonts.robotoTextTheme(baseTheme.textTheme),
      // Add other customizations: button themes, card themes, etc.
      cardTheme: baseTheme.cardTheme.copyWith(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple, // Button background
          foregroundColor: Colors.white, // Button text/icon color
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  ThemeData get darkTheme {
    final baseTheme = ThemeData.dark(useMaterial3: true);
    return baseTheme.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark, // Important for dark theme colors
      ),
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: Colors.deepPurple.shade700,
        foregroundColor: Colors.white,
        elevation: 4.0,
        toolbarHeight: 65.0, // Increased height for mobile friendliness
        titleTextStyle: GoogleFonts.roboto(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      textTheme: GoogleFonts.robotoTextTheme(baseTheme.textTheme).apply(
          bodyColor: Colors.white70,
          displayColor: Colors.white), // Adjust text colors
      cardTheme: baseTheme.cardTheme.copyWith(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        color: Colors.grey.shade800, // Darker card background
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple.shade400, // Button background
          foregroundColor: Colors.white, // Button text/icon color
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      // Add other customizations
    );
  }

  static TextTheme _buildTextTheme({required bool isDark}) {
    final baseColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: baseColor,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: baseColor,
        letterSpacing: -0.25,
        height: 1.3,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        color: baseColor.withOpacity(isDark ? 0.9 : 0.8),
        height: 1.5,
        letterSpacing: 0.1,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 16,
        color: baseColor.withOpacity(isDark ? 0.9 : 0.8),
        height: 1.5,
        letterSpacing: 0.1,
      ),
      labelLarge: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: 0.5,
      ),
    );
  }

  static AppBarTheme _buildAppBarTheme(
      {required bool isDark, required ColorScheme colorScheme}) {
    return AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
        letterSpacing: 0.1,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface.withOpacity(0.8)),
      actionsIconTheme:
          IconThemeData(color: colorScheme.onSurface.withOpacity(0.8)),
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme(
      {required bool isDark, required ColorScheme colorScheme}) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 1,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.inlineSpacing * 3,
          vertical: AppSpacing.inlineSpacing * 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMedium),
        ),
        textStyle: _buildTextTheme(isDark: isDark).labelLarge,
      ),
    );
  }

  static InputDecorationTheme _buildInputDecorationTheme(
      {required bool isDark, required ColorScheme colorScheme}) {
    return InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceVariant.withOpacity(isDark ? 0.5 : 0.7),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMedium),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMedium),
        borderSide: BorderSide(
          color: colorScheme.outline.withOpacity(0.5),
          width: 1.0,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusMedium),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 1.5,
        ),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.inlineSpacing * 2,
        vertical: AppSpacing.inlineSpacing * 1.5,
      ),
      hintStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 16,
        color: colorScheme.onSurface.withOpacity(0.5),
      ),
    );
  }

  static CardTheme _buildCardTheme(
      {required bool isDark, required ColorScheme colorScheme}) {
    return CardTheme(
      elevation: isDark ? 1 : 2,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusLarge),
        side: isDark
            ? BorderSide(
                color: colorScheme.outline.withOpacity(0.5), width: 0.5)
            : BorderSide.none,
      ),
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
    );
  }

  static ScrollbarThemeData _buildScrollbarTheme(
      {required bool isDark, required ColorScheme colorScheme}) {
    return ScrollbarThemeData(
      thumbVisibility: MaterialStateProperty.all(false),
      thickness: MaterialStateProperty.all(6.0),
      radius: const Radius.circular(3.0),
      thumbColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.hovered) ||
            states.contains(MaterialState.dragged)) {
          return colorScheme.onSurface.withOpacity(0.6);
        }
        return colorScheme.onSurface.withOpacity(0.3);
      }),
      trackVisibility: MaterialStateProperty.all(false),
      interactive: true,
    );
  }

  static SnackBarThemeData _buildSnackBarTheme(
      {required bool isDark, required ColorScheme colorScheme}) {
    return SnackBarThemeData(
      backgroundColor: isDark ? colorScheme.surface : colorScheme.onSurface,
      contentTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: isDark ? colorScheme.onSurface : colorScheme.surface,
        fontSize: 14,
      ),
      actionTextColor: isDark ? colorScheme.primary : colorScheme.primary,
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSmall)),
      behavior: SnackBarBehavior.floating,
    );
  }

  // Gradient getters for widgets
  LinearGradient get primaryGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _primaryGradient,
        stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
      );

  LinearGradient get secondaryGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _secondaryGradient,
        stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
      );

  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _accentGradient,
        stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
      );
}
