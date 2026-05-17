import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/role_selection_screen.dart';

void main() {
  runApp(const KhedmatgarApp());
}

class KhedmatgarApp extends StatelessWidget {
  const KhedmatgarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Khedmatgar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00C853), // Emerald Green
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Deep Slate
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C853),
          brightness: Brightness.dark,
          secondary: const Color(0xFFFFD700), // Amber Gold
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const RoleSelectionScreen(),
    );
  }
}
