import 'package:flutter/material.dart';
import 'package:read_aloud/ui/routes/app_router.dart';

void main() {
  runApp(const ReadAloudApp());
}

class ReadAloudApp extends StatelessWidget {
  const ReadAloudApp({super.key});

  static final _router = AppRouter.create();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Read Aloud',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7F9),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      routerConfig: _router,
    );
  }
}
