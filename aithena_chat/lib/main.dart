import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'services/chat_provider.dart';
import 'theme/theme_provider.dart';
import 'screens/chat_screen.dart';
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
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Otto',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.currentTheme,
            initialRoute: '/',
            routes: {
              '/': (context) => const ChatScreen(),
              '/spacing-example': (context) => const SpacingExampleScreen(),
            },
          );
        },
      ),
    );
  }
} 