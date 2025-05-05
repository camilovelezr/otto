import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'services/chat_provider.dart';
import 'services/auth_provider.dart';
import 'services/auth_service.dart'; // Import AuthService
import 'services/encryption_service.dart'; // Import EncryptionService
import 'services/chat_service.dart'; // Import ChatService
import 'theme/theme_provider.dart';
import 'package:google_fonts/google_fonts.dart'; // Import Google Fonts
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/model_management_screen.dart';
import 'screens/export_identity_screen.dart';
import 'screens/import_identity_screen.dart';
import 'config/env_config.dart';
import 'theme/app_spacing_example.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure system UI for desktop
  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ));
  }

  try {
    // Load environment configuration with error handling
    await EnvConfig.load().catchError((error) {
      // Log the error but continue app initialization
      debugPrint('Error loading environment configuration: $error');
      // In a real app, you might want to show an error dialog or handle differently
    });
  } catch (e) {
    // Catch any errors from environment loading to prevent app crash
    debugPrint('Caught error during environment loading: $e');
  }

  // Instantiate services (AuthService first, then EncryptionService)
  final authService = AuthService();
  final encryptionService = EncryptionService(authService);

  // Initialize AuthService (which now initializes EncryptionService internally)
  // Handle potential init errors
  try {
    await authService.init();
    debugPrint(
        'AuthService initialized successfully (includes EncryptionService init)');
  } catch (e) {
    debugPrint('Error initializing AuthService: $e');
    // Handle critical initialization failure (e.g., show error screen)
  }

  runApp(MyApp(authService: authService, encryptionService: encryptionService));
}

class MyApp extends StatelessWidget {
  final AuthService authService;
  final EncryptionService encryptionService;

  const MyApp(
      {super.key, required this.authService, required this.encryptionService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Provide the pre-initialized services
        Provider<AuthService>.value(value: authService),
        Provider<EncryptionService>.value(value: encryptionService),

        ChangeNotifierProvider(create: (_) => ThemeProvider()),

        // Update ChatProvider to get EncryptionService from Provider
        ChangeNotifierProvider(
            create: (context) => ChatProvider(
                chatService: ChatService(
                    // Read services from context/provider
                    authService: context.read<AuthService>(),
                    encryptionService: context.read<EncryptionService>()))),
        // Update AuthProvider to get services from Provider
        ChangeNotifierProvider(
            create: (context) => AuthProvider(
                  context.read<AuthService>(),
                  context.read<EncryptionService>(), // Pass EncryptionService
                  // Consider providing ModelService too if needed
                )),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Otto',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme.copyWith(
              textTheme: GoogleFonts.robotoTextTheme(
                  themeProvider.lightTheme.textTheme),
              platform: TargetPlatform.macOS,
            ),
            darkTheme: themeProvider.darkTheme.copyWith(
              textTheme: GoogleFonts.robotoTextTheme(
                  themeProvider.darkTheme.textTheme),
              platform: TargetPlatform.macOS,
            ),
            themeMode: themeProvider.themeMode,
            initialRoute: '/',
            routes: {
              '/': (context) => const AuthWrapper(),
              '/login': (context) => const LoginScreen(),
              '/register': (context) => const RegisterScreen(),
              '/chat': (context) => const ChatScreen(),
              '/spacing-example': (context) => const SpacingExampleScreen(),
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // Log state every time AuthWrapper rebuilds
    debugPrint(
        '[AuthWrapper] Build: isLoading=${authProvider.isLoading}, keyImportIsRequired=${authProvider.keyImportIsRequired}, isLoggedIn=${authProvider.isLoggedIn}');

    // Show loading spinner while checking auth state
    if (authProvider.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // If key import is required, show the ImportIdentityScreen
    if (authProvider.keyImportIsRequired) {
      debugPrint(
          '[AuthWrapper] Key import required, showing ImportIdentityScreen.');
      return const ImportIdentityScreen();
    }

    // Redirect based on auth state
    if (authProvider.isLoggedIn) {
      // Set the user's username in ChatProvider
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          chatProvider.setUserId(
              currentUser.id?.toString() ??
                  currentUser.username, // Keep ID logic
              username: currentUser.username, // Keep username for auth header
              name: currentUser.name // Pass the display name
              );
        });
      }
      return const ChatScreen();
    } else {
      return const LoginScreen();
    }
  }
}
