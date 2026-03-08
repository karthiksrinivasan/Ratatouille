import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

class RatatouilleApp extends StatelessWidget {
  final GoRouter router;

  const RatatouilleApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ratatouille',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
