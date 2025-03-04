import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'services/chat_provider.dart';
import 'services/auth_provider.dart';
import 'theme/theme_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'config/env_config.dart';
import 'theme/app_spacing_example.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Otto',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.currentTheme,
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
            currentUser.id?.toString() ?? currentUser.username,
            username: currentUser.username
          );
        });
      }
      return const ChatScreen();
    } else {
      return const LoginScreen();
    }
  }
} 