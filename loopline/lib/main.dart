import 'package:flutter/material.dart';
import 'package:loopline/frontend/pages/input_screen.dart';
 
void main() => runApp(const ArbitrageApp());
 
class ArbitrageApp extends StatelessWidget {
  const ArbitrageApp({super.key});
 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loopline',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE8A33D),
          onPrimary: Color(0xFF1A1200),
          surface: Color(0xFF16212C),
          secondary: Color(0xFF34C77B),
          error: Color(0xFFE1636B),
        ),
        scaffoldBackgroundColor: const Color(0xFF0E1620),
        cardColor: const Color(0xFF16212C),
        dividerColor: const Color(0xFF26374A),
      ),
      home: const InputScreen(),
    );
  }
}