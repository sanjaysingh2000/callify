import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get light {
    const primary = Color(0xFF0E7490);
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F8FA),
      appBarTheme: const AppBarTheme(centerTitle: false),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(
            backgroundColor: Color(0xFF0D171A),
          ),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(
            backgroundColor: Color(0xFF0D171A),
          ),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(
            backgroundColor: Color(0xFF0D171A),
          ),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(
            backgroundColor: Color(0xFF0D171A),
          ),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(
            backgroundColor: Color(0xFF0D171A),
          ),
          TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(
            backgroundColor: Color(0xFF0D171A),
          ),
        },
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }
}
