import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'is_dark_mode';
  late SharedPreferences _prefs;
  bool _isDarkMode;

  ThemeProvider() : _isDarkMode = true {
    _loadTheme();
  }

  bool get isDarkMode => _isDarkMode;

  static const _primaryGradient = [Color(0xFF7B61FF), Color(0xFF9C8FFF)];
  static const _secondaryGradient = [Color(0xFFFF6B6B), Color(0xFFFF8E8E)];
  static const _accentGradient = [Color(0xFF48DAD0), Color(0xFF76E8E0)];

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

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        background: const Color(0xFF1A1A2E),
        surface: const Color(0xFF252A48),
        primary: _primaryGradient[0],
        secondary: _secondaryGradient[0],
        tertiary: _accentGradient[0],
        onBackground: Colors.white,
        onSurface: Colors.white,
        onPrimary: Colors.white,
        surfaceTint: Colors.transparent,
      ),
      textTheme: _buildTextTheme(isDark: true),
      appBarTheme: _buildAppBarTheme(isDark: true),
      elevatedButtonTheme: _buildElevatedButtonTheme(isDark: true),
      inputDecorationTheme: _buildInputDecorationTheme(isDark: true),
      cardTheme: _buildCardTheme(isDark: true),
      scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF3C3C3C),
        thickness: 1,
      ),
      iconTheme: IconThemeData(
        color: Colors.white.withOpacity(0.9),
        size: 24,
      ),
      snackBarTheme: _buildSnackBarTheme(isDark: true),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        background: const Color(0xFFF8F9FF),
        surface: Colors.white,
        primary: _primaryGradient[0],
        secondary: _secondaryGradient[0],
        tertiary: _accentGradient[0],
        onBackground: const Color(0xFF1A1A2E),
        onSurface: const Color(0xFF1A1A2E),
        onPrimary: Colors.white,
        surfaceTint: Colors.transparent,
      ),
      textTheme: _buildTextTheme(isDark: false),
      appBarTheme: _buildAppBarTheme(isDark: false),
      elevatedButtonTheme: _buildElevatedButtonTheme(isDark: false),
      inputDecorationTheme: _buildInputDecorationTheme(isDark: false),
      cardTheme: _buildCardTheme(isDark: false),
      scaffoldBackgroundColor: const Color(0xFFF8F9FF),
      dividerTheme: DividerThemeData(
        color: const Color(0xFF1A1A2E).withOpacity(0.1),
        thickness: 1,
      ),
      iconTheme: IconThemeData(
        color: const Color(0xFF1A1A2E).withOpacity(0.9),
        size: 24,
      ),
      snackBarTheme: _buildSnackBarTheme(isDark: false),
    );
  }

  static TextTheme _buildTextTheme({required bool isDark}) {
    final baseColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: baseColor,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      displayMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: baseColor,
        letterSpacing: -0.25,
        height: 1.3,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: baseColor.withOpacity(0.9),
        height: 1.5,
        letterSpacing: 0.1,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        color: baseColor.withOpacity(0.9),
        height: 1.5,
        letterSpacing: 0.1,
      ),
    );
  }

  static AppBarTheme _buildAppBarTheme({required bool isDark}) {
    final baseColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    return AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: isDark ? const Color(0xFF212121) : Colors.white,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: baseColor,
        letterSpacing: -0.5,
      ),
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme({required bool isDark}) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primaryGradient[0],
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static InputDecorationTheme _buildInputDecorationTheme({required bool isDark}) {
    return InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF252A48) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: _primaryGradient[0].withOpacity(0.2),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: _primaryGradient[0].withOpacity(0.2),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: _primaryGradient[0],
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.all(16),
      hintStyle: TextStyle(
        fontFamily: 'Inter',
        color: (isDark ? Colors.white : const Color(0xFF1A1A2E)).withOpacity(0.5),
      ),
    );
  }

  static CardTheme _buildCardTheme({required bool isDark}) {
    return CardTheme(
      elevation: 4,
      shadowColor: _primaryGradient[0].withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      color: isDark ? const Color(0xFF252A48) : Colors.white,
      clipBehavior: Clip.antiAlias,
    );
  }

  static SnackBarThemeData _buildSnackBarTheme({required bool isDark}) {
    return SnackBarThemeData(
      backgroundColor: isDark ? const Color(0xFF60A5FA) : _primaryGradient[0],
      contentTextStyle: const TextStyle(
        fontFamily: 'Inter',
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  // Gradient getters for widgets
  LinearGradient get primaryGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _primaryGradient,
      );

  LinearGradient get secondaryGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _secondaryGradient,
      );

  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _accentGradient,
      );
} 