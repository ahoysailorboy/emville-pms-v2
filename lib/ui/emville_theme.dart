import 'package:flutter/material.dart';

abstract final class Emville {
  static const forest = Color(0xFF244E3E);
  static const ink = Color(0xFF203E34);
  static const ivory = Color(0xFFF8F6F0);
  static const paper = Color(0xFFFFFEFA);
  static const sage = Color(0xFFE8EDDF);
  static const gold = Color(0xFFB98B36);
  static const muted = Color(0xFF788277);
  static const line = Color(0xFFE3E5DB);
  static const logo = 'assets/brand/emville-logo.png';
  static const veranda = 'assets/images/property/veranda.jpg';
  static const bedroom = 'assets/images/property/bedroom.jpg';
  static const pool = 'assets/images/property/pool.jpg';

  static TextStyle heading(double size) => TextStyle(
        fontFamily: 'EmvilleSerif',
        fontFamilyFallback: const ['Roboto', 'Georgia', 'serif'],
        fontSize: size,
        color: ink,
        fontWeight: FontWeight.w400,
        height: 1.2,
      );

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(seedColor: forest).copyWith(
      primary: forest,
      onPrimary: paper,
      secondary: gold,
      surface: ivory,
      onSurface: ink,
      outline: line,
      surfaceContainerHighest: sage,
    );
    final base = ThemeData(
        useMaterial3: true, fontFamily: 'Roboto', colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: ivory,
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: ivory,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: line)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: forest, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(
            fontFamily: 'Roboto', fontSize: 12, fontWeight: FontWeight.w600),
        backgroundColor: forest,
        foregroundColor: paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 38),
        textStyle: const TextStyle(fontFamily: 'Roboto', fontSize: 11),
        foregroundColor: forest,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      )),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: ivory,
        indicatorColor: sage,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      dialogTheme: DialogThemeData(
          backgroundColor: ivory,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    );
  }
}
