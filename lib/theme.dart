import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Color Palette
  static const Color emeraldGreen = Color(0xFF0F5132);
  static const Color freshWhite = Color(0xFFF8F9FA);
  static const Color goldenOrange = Color(0xFFFD7E14);
  static const Color softGray = Color(0xFFE9ECEF);
  static const Color darkText = Color(0xFF212529);

  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: emeraldGreen,
      scaffoldBackgroundColor: freshWhite,

      // Define the default Font Family
      textTheme: GoogleFonts.poppinsTextTheme().apply(
        bodyColor: darkText,
        displayColor: emeraldGreen,
      ),

      // FIX: Changed 'CardTheme' to 'CardThemeData' for Flutter 3.27+
      cardTheme: CardThemeData(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
        // Margin is handled by the widget layout, not the global theme
      ),

      // App Bar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: emeraldGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),

      // Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: emeraldGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}
