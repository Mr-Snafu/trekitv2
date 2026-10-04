import 'package:flutter/material.dart';

import '../core/theme/trekit_theme.dart';
import '../features/auth/presentation/auth_gate.dart';

class TrekItApp extends StatelessWidget {
  const TrekItApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrekIt',
      debugShowCheckedModeBanner: false,
      theme: TrekItTheme.light,
      home: home ?? const AuthGate(),
    );
  }
}
