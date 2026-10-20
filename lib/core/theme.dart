import 'package:flutter/material.dart';

/// كل ألوان التطبيق في مكان واحد.
class Brand {
  static const petrol = Color(0xFF0E3B43); // الهيدر
  static const teal = Color(0xFF1FA39A); // الأزرار والعناصر النشطة
  static const tealDark = Color(0xFF35C4BA); // نفس اللون في الوضع الداكن
  static const amber = Color(0xFFE8A33D); // تنبيهات ووقائية مستحقة
  static const red = Color(0xFFD6574A); // أعطال وأولوية عالية
  static const green = Color(0xFF2E9E6B); // يعمل / متاح
  static const bgLight = Color(0xFFEAF2F1);
  static const bgDark = Color(0xFF081518);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final primary = dark ? Brand.tealDark : Brand.teal;
  final scheme = ColorScheme.fromSeed(seedColor: Brand.teal, brightness: b).copyWith(
    primary: primary,
    onPrimary: dark ? Colors.black : Colors.white,
    error: Brand.red,
    surface: dark ? const Color(0xFF0F2227) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? Brand.bgDark : Brand.bgLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.petrol,
      foregroundColor: Colors.white,
      iconTheme: IconThemeData(color: Colors.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 52)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
    ),
  );
}
