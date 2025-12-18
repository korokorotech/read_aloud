import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:read_aloud/ui/routes/app_router.dart';

void main() {
  initApp();
  runApp(const ReadAloudApp());
}

void initApp() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
}

class ReadAloudApp extends StatelessWidget {
  const ReadAloudApp({super.key});

  static final _router = AppRouter.create();

  @override
  Widget build(BuildContext context) {
    final fontFamily = Platform.isIOS ? 'Hiragino Sans' : 'Noto Sans CJK JP';
    final fontFallback = Platform.isIOS
        ? const ['Hiragino Sans', 'YuGothic', 'Hiragino Kaku Gothic ProN']
        : const ['Noto Sans CJK JP', 'Noto Sans JP', 'sans-serif'];

    return MaterialApp.router(
      title: 'Read Aloud',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7F9),
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
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
