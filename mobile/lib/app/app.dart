import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class RatatouilleApp extends StatelessWidget {
  const RatatouilleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ratatouille',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
