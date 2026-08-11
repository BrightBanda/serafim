import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serafim/src/presentation/view/auth_gate.dart';
import 'package:serafim/src/utils/themes/app_colors.dart';

void main() {
  runApp(const ProviderScope(child: SerafimApp()));
}

class SerafimApp extends StatelessWidget {
  const SerafimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Serafim',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.paper,
      ),
      home: const AuthGate(),
    );
  }
}
