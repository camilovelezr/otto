import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/chat_provider.dart';
import 'screens/chat_screen.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = true;
  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Aithena Chat',
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            home: const ChatScreen(),
          );
        },
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        background: const Color(0xFF1A1A2E),
        surface: const Color(0xFF252A48),
        primary: const Color(0xFF7B61FF),
        secondary: const Color(0xFFFF6B6B),
        tertiary: const Color(0xFF48DAD0),
        onBackground: Colors.white,
        onSurface: Colors.white,
        onPrimary: Colors.white,
        surfaceTint: Colors.transparent,
      ),
      textTheme: GoogleFonts.openSansTextTheme().copyWith(
        displayLarge: GoogleFonts.openSans(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.openSans(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -0.25,
        ),
        bodyLarge: GoogleFonts.openSans(
          fontSize: 14,
          color: Colors.white.withOpacity(0.9),
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.openSans(
          fontSize: 14,
          color: Colors.white.withOpacity(0.9),
          height: 1.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF212121),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.openSans(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7B61FF),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.openSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF252A48),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: const Color(0xFF7B61FF).withOpacity(0.3),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0xFF7B61FF),
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.all(16),
        hintStyle: GoogleFonts.openSans(
          color: Colors.white.withOpacity(0.5),
        ),
      ),
      cardTheme: CardTheme(
        elevation: 4,
        shadowColor: const Color(0xFF7B61FF).withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: const Color(0xFF252A48),
        clipBehavior: Clip.antiAlias,
      ),
      scaffoldBackgroundColor: const Color(0xFF1A1A2E),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF3C3C3C),
        thickness: 1,
      ),
      iconTheme: IconThemeData(
        color: Colors.white.withOpacity(0.9),
        size: 24,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF60A5FA),
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        background: const Color(0xFFF8F9FF),
        surface: Colors.white,
        primary: const Color(0xFF7B61FF),
        secondary: const Color(0xFFFF6B6B),
        tertiary: const Color(0xFF48DAD0),
        onBackground: const Color(0xFF1A1A2E),
        onSurface: const Color(0xFF1A1A2E),
        onPrimary: Colors.white,
        surfaceTint: Colors.transparent,
      ),
      textTheme: GoogleFonts.openSansTextTheme().copyWith(
        displayLarge: GoogleFonts.openSans(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF212121),
          letterSpacing: -0.5,
        ),
        displayMedium: GoogleFonts.openSans(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF212121),
          letterSpacing: -0.25,
        ),
        bodyLarge: GoogleFonts.openSans(
          fontSize: 14,
          color: const Color(0xFF212121).withOpacity(0.9),
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.openSans(
          fontSize: 14,
          color: const Color(0xFF212121).withOpacity(0.9),
          height: 1.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.openSans(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF212121),
          letterSpacing: -0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7B61FF),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.openSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: const Color(0xFF7B61FF).withOpacity(0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: const Color(0xFF7B61FF).withOpacity(0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0xFF7B61FF),
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.all(16),
        hintStyle: GoogleFonts.openSans(
          color: const Color(0xFF1A1A2E).withOpacity(0.5),
        ),
      ),
      cardTheme: CardTheme(
        elevation: 4,
        shadowColor: const Color(0xFF7B61FF).withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F7F7),
      dividerTheme: DividerThemeData(
        color: const Color(0xFF212121).withOpacity(0.1),
        thickness: 1,
      ),
      iconTheme: IconThemeData(
        color: const Color(0xFF212121).withOpacity(0.9),
        size: 24,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF60A5FA),
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
