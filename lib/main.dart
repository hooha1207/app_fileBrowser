import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:app_filepicker/screens/home_screen.dart';
import 'package:app_filepicker/providers/font_provider.dart';
import 'package:app_filepicker/providers/theme_provider.dart';
import 'package:app_filepicker/core/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FontSizeProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer2<FontSizeProvider, ThemeProvider>(
        builder: (context, fontProvider, themeProvider, child) {
          return MaterialApp(
            title: 'My Files',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,

            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
