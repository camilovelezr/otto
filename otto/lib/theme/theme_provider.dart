import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_spacing.dart'; // Import for spacing constants
import 'app_colors.dart'; // Import base colors

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'is_dark_mode';
  late SharedPreferences _prefs;
  bool _isDarkMode;

  ThemeProvider() : _isDarkMode = true {
    _loadTheme();
  }

  bool get isDarkMode => _isDarkMode;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

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

  Future<void> _loadTheme() async {
    _prefs = await SharedPreferences.getInstance();
    _isDarkMode = _prefs.getBool(_themeKey) ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _prefs.setBool(_themeKey, _isDarkMode);
    notifyListeners();
  }

  ThemeData get currentTheme => _isDarkMode ? darkTheme : lightTheme;

  // Add getters for the themes
  ThemeData get lightTheme => _lightThemeData; // Expose light theme
  ThemeData get darkTheme => _darkThemeData; // Expose dark theme

  // --- Light Theme Definition ---
  // Make the theme definitions static private vars or instance vars if preferred
  static final ThemeData _lightThemeData = (() {
    final baseColorScheme = ColorScheme.light(
      brightness: Brightness.light,
      primary: AppColors.primary, // Use base color
      secondary: AppColors.secondary,
      tertiary: AppColors.accent,
      background: const Color(0xFFF4F5F7),
      surface: Colors.white,
      error: AppColors.error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onBackground: const Color(0xFF1A1A2E),
      onSurface: const Color(0xFF1A1A2E),
      onError: Colors.white,
      surfaceTint: Colors.transparent,
      primaryContainer: AppColors.primary.withOpacity(0.1),
      onPrimaryContainer: AppColors.primary,
      secondaryContainer: AppColors.secondary.withOpacity(0.1),
      onSecondaryContainer: AppColors.secondary,
      tertiaryContainer: AppColors.accent.withOpacity(0.1),
      onTertiaryContainer: AppColors.accent,
      errorContainer: AppColors.error.withOpacity(0.1),
      onErrorContainer: AppColors.error,
      surfaceVariant: const Color(0xFFEEEEF2),
      onSurfaceVariant: const Color(0xFF333642),
      outline: const Color(0xFFD0D2DA),
      outlineVariant: const Color(0xFFE4E6EC),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: baseColorScheme,
      scaffoldBackgroundColor: baseColorScheme.background,
      textTheme: _buildTextTheme(isDark: false),
      appBarTheme: _buildAppBarTheme(isDark: false, colorScheme: baseColorScheme),
      elevatedButtonTheme: _buildElevatedButtonTheme(isDark: false, colorScheme: baseColorScheme),
      inputDecorationTheme: _buildInputDecorationTheme(isDark: false, colorScheme: baseColorScheme),
      cardTheme: _buildCardTheme(isDark: false, colorScheme: baseColorScheme),
      dividerTheme: DividerThemeData(
        color: baseColorScheme.outline.withOpacity(0.5),
        thickness: 1,
      ),
      iconTheme: IconThemeData(
        color: baseColorScheme.onSurface.withOpacity(0.8),
        size: 24,
      ),
      scrollbarTheme: _buildScrollbarTheme(isDark: false, colorScheme: baseColorScheme),
      snackBarTheme: _buildSnackBarTheme(isDark: false, colorScheme: baseColorScheme),
    );
  })();

  static ThemeData _darkThemeData = (() {
    final baseColorScheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      tertiary: AppColors.accent,
      background: const Color(0xFF0F0F17),
      surface: const Color(0xFF1E1E2E),
      error: AppColors.error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onBackground: Colors.white,
      onSurface: Colors.white,
      onError: Colors.black,
      surfaceTint: Colors.transparent,
      primaryContainer: AppColors.primary.withOpacity(0.25),
      onPrimaryContainer: Colors.white,
      secondaryContainer: AppColors.secondary.withOpacity(0.2),
      onSecondaryContainer: Colors.white,
      tertiaryContainer: AppColors.accent.withOpacity(0.2),
      onTertiaryContainer: Colors.white,
      errorContainer: AppColors.error.withOpacity(0.3),
      onErrorContainer: Colors.white,
      surfaceVariant: const Color(0xFF2A2A3F),
      onSurfaceVariant: const Color(0xDDFFFFFF),
      outline: const Color(0xFF41435A),
      outlineVariant: const Color(0xFF2A2A3F),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: baseColorScheme,
      scaffoldBackgroundColor: baseColorScheme.background,
      textTheme: _buildTextTheme(isDark: true),
      appBarTheme: _buildAppBarTheme(isDark: true, colorScheme: baseColorScheme),
      elevatedButtonTheme: _buildElevatedButtonTheme(isDark: true, colorScheme: baseColorScheme),
      inputDecorationTheme: _buildInputDecorationTheme(isDark: true, colorScheme: baseColorScheme),
      cardTheme: _buildCardTheme(isDark: true, colorScheme: baseColorScheme),
      dividerTheme: DividerThemeData(
        color: baseColorScheme.outline.withOpacity(0.5),
        thickness: 1,
      ),
      iconTheme: IconThemeData(
        color: baseColorScheme.onSurface.withOpacity(0.9),
        size: 24,
      ),
      scrollbarTheme: _buildScrollbarTheme(isDark: true, colorScheme: baseColorScheme),
      snackBarTheme: _buildSnackBarTheme(isDark: true, colorScheme: baseColorScheme),
    );
  })();

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

  static AppBarTheme _buildAppBarTheme({required bool isDark, required ColorScheme colorScheme}) {
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
      actionsIconTheme: IconThemeData(color: colorScheme.onSurface.withOpacity(0.8)),
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme({required bool isDark, required ColorScheme colorScheme}) {
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

  static InputDecorationTheme _buildInputDecorationTheme({required bool isDark, required ColorScheme colorScheme}) {
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

  static CardTheme _buildCardTheme({required bool isDark, required ColorScheme colorScheme}) {
    return CardTheme(
      elevation: isDark ? 1 : 2,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusLarge),
        side: isDark ? BorderSide(color: colorScheme.outline.withOpacity(0.5), width: 0.5) : BorderSide.none,
      ),
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
    );
  }

  static ScrollbarThemeData _buildScrollbarTheme({required bool isDark, required ColorScheme colorScheme}) {
    return ScrollbarThemeData(
      thumbVisibility: MaterialStateProperty.all(false),
      thickness: MaterialStateProperty.all(6.0),
      radius: const Radius.circular(3.0),
      thumbColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.hovered) || states.contains(MaterialState.dragged)) {
          return colorScheme.onSurface.withOpacity(0.6);
        }
        return colorScheme.onSurface.withOpacity(0.3);
      }),
      trackVisibility: MaterialStateProperty.all(false),
      interactive: true,
    );
  }

  static SnackBarThemeData _buildSnackBarTheme({required bool isDark, required ColorScheme colorScheme}) {
    return SnackBarThemeData(
      backgroundColor: isDark ? colorScheme.surface : colorScheme.onSurface,
      contentTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: isDark ? colorScheme.onSurface : colorScheme.surface,
        fontSize: 14,
      ),
      actionTextColor: isDark ? colorScheme.primary : colorScheme.primary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.borderRadiusSmall)),
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