import 'package:flutter/material.dart';

import '../core/config/app_environment.dart';
import 'app_shell.dart';
import 'app_theme.dart';

class ExpiryManagementApp extends StatelessWidget {
  const ExpiryManagementApp({required this.environment, super.key});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expiry Manager',
      debugShowCheckedModeBanner: environment.flavor != AppFlavor.production,
      theme: AppTheme.light,
      home: const AppShell(),
    );
  }
}
