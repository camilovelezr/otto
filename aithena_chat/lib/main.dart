import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/chat_provider.dart';
import 'theme/theme_provider.dart';
import 'screens/chat_screen.dart';
import 'config/env_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvConfig.load();
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
            title: 'Aithena Chat',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.currentTheme,
            home: const ChatScreen(),
          );
        },
      ),
    );
  }
} 