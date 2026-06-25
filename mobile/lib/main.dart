import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIG Microbuses Santa Cruz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF12141C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0D99FF),      // neon blue accent
          secondary: Color(0xFF00E676),    // green
          surface: Color(0xFF171923),      // sheet background
          background: Color(0xFF12141C),
          onPrimary: Colors.white,
          onSurface: Colors.white,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white70),
          bodyMedium: TextStyle(color: Colors.white60),
        ),
        dividerColor: Colors.white12,
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF0D99FF),
          thumbColor: Color(0xFF0D99FF),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
