import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';
import 'package:getready_bmx/screens/login_screen.dart';
import 'package:getready_bmx/screens/home_screen.dart';
import 'package:getready_bmx/screens/live_screen.dart';
import 'package:getready_bmx/screens/leaderboard_screen.dart';
import 'package:getready_bmx/screens/settings_screen.dart';
import 'package:getready_bmx/screens/records_screen.dart';
import 'package:getready_bmx/providers/theme_provider.dart'; // Importa el ThemeProvider
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    //options: DefaultFirebaseOptions.currentPlatform,
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            initialRoute: '/',
            theme: themeProvider.themeData, // Usa el ThemeData dinámico
            routes: {
              '/': (context) => Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      return auth.isAuthenticated
                          ? HomeScreen()
                          : LoginScreen();
                    },
                  ),
              '/home': (context) => HomeScreen(),
              '/live': (context) => LiveScreen(),
              '/leaderboard': (context) => LeaderboardScreen(),
              '/settings': (context) => SettingsScreen(),
              '/records': (context) => RecordsScreen(),
              '/login': (context) => LoginScreen(),
            },
          );
        },
      ),
    );
  }
}
