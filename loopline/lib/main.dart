import 'package:flutter/material.dart';
import 'package:loopline_frontend/frontend/pages/input_screen.dart';
 
void main() => runApp(const ArbitrageApp());
 
class ArbitrageApp extends StatelessWidget {
  const ArbitrageApp({super.key});
 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arbitrage Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF2ECC9A),
        scaffoldBackgroundColor: const Color(0xFF0E1116),
      ),
      home: const InputScreen(),
    );
  }
}