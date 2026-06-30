// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'pages/home_page.dart';
import 'player/locale_fix.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/mubu_models.dart';
import 'models/mubu_hive.dart';
import 'api/mubu_api_client.dart';
import 'api/jp_api_impl.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  setNumericLocaleToC();
  MediaKit.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(VideoItemAdapter());
  Hive.registerAdapter(NodeSpeedRecordAdapter());
  Hive.registerAdapter(SourceProbeRecordAdapter());

  await Future.wait([
    Hive.openBox<VideoItem>('bookmarks'),
    Hive.openBox<VideoItem>('history'),
    Hive.openBox<String>('config'),
    Hive.openBox<NodeSpeedRecord>('node_speeds'),
    Hive.openBox<SourceProbeRecord>('source_probes'),
  ]);

  // Initialize Mubu API client
  MubuApiClient.instance = JpApiClientImpl();
  try {
    // Attempt early initialization to minimize the window where imgDomain is empty.
    // Use a timeout to ensure it doesn't block app startup if offline.
    await MubuApiClient.instance.init().timeout(const Duration(seconds: 4));
  } catch (_) {
    // API initialization might fail or timeout on cold start without network.
    // It will be safely retried inside home_page.dart when loading categories.
  }

  runApp(const MubuApp());
}

class MubuApp extends StatelessWidget {
  const MubuApp({super.key});

  // Design system colors
  static const Color kPrimaryRed = Color(0xFFE50914);
  static const Color kBackgroundDark = Color(0xFF070708);
  static const Color kSurfaceDark = Color(0xFF0A0A0C);
  static const Color kCardDark = Color(0xFF121215);
  static const Color kGlassPanel = Color(0xFF16161A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '幕布 CINE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBackgroundDark,
        colorScheme: const ColorScheme.dark(
          primary: kPrimaryRed,
          secondary: Color(0xFFFF2D2D),
          surface: kSurfaceDark,
          onPrimary: Colors.white,
          onSurface: Colors.white,
        ),
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: kCardDark,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          headlineMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(color: Colors.white70),
          bodyMedium: TextStyle(color: Colors.white60),
          bodySmall: TextStyle(color: Colors.white38),
        ),
      ),
      home: const HomePage(),
    );
  }
}
