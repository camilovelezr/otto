import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'services/chat_provider.dart';
import 'services/auth_provider.dart';
import 'services/encryption_service.dart'; // Import EncryptionService
import 'services/chat_service.dart'; // Import ChatService
import 'theme/theme_provider.dart';
import 'package:google_fonts/google_fonts.dart'; // Import Google Fonts
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
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
  
  // Initialize encryption service and fetch server public key
  final encryptionService = EncryptionService();
  try {
    await encryptionService.initializeKeys();
    await encryptionService.fetchAndStoreServerPublicKey(EnvConfig.backendUrl);
    debugPrint('Successfully initialized encryption and fetched server public key');
  } catch (e) {
    debugPrint('Error initializing encryption: $e');
  }
  
  runApp(MyApp(encryptionService: encryptionService));
}

class MyApp extends StatelessWidget {
  final EncryptionService encryptionService;
  
  const MyApp({Key? key, required this.encryptionService}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Provide the pre-initialized EncryptionService
        Provider.value(value: encryptionService),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        // Create ChatService within ChatProvider's create, passing EncryptionService
        ChangeNotifierProvider(
          create: (context) => ChatProvider(
             chatService: ChatService(
               encryptionService: encryptionService // Use the pre-initialized service
             )
          )
        ),
        ChangeNotifierProvider(
          create: (context) => AuthProvider()
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Otto',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.currentTheme.copyWith(
              platform: TargetPlatform.macOS,
              scaffoldBackgroundColor: Colors.white,
              textTheme: GoogleFonts.robotoTextTheme(
                themeProvider.currentTheme.textTheme,
              ),
              colorScheme: themeProvider.currentTheme.colorScheme.copyWith(
                background: Colors.white,
                surface: Colors.white,
              ),
            ),
            darkTheme: themeProvider.currentTheme.copyWith(
              platform: TargetPlatform.macOS,
              scaffoldBackgroundColor: const Color(0xFF121212),
              textTheme: GoogleFonts.robotoTextTheme(
                themeProvider.currentTheme.textTheme.apply(
                  bodyColor: Colors.white, 
                  displayColor: Colors.white
                ),
              ),
              colorScheme: themeProvider.currentTheme.colorScheme.copyWith(
                background: const Color(0xFF121212),
                surface: const Color(0xFF121212),
              ),
            ),
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
    
    // Show loading spinner while checking auth state
    if (authProvider.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    // Redirect based on auth state
    if (authProvider.isLoggedIn) {
      // Set the user's username in ChatProvider
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          chatProvider.setUserId(
            currentUser.id?.toString() ?? currentUser.username, // Keep ID logic
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
