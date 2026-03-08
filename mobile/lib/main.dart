import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'core/env_config.dart';
import 'core/api_client.dart';
import 'core/auth_service.dart';
import 'core/connectivity.dart';
import 'features/recipes/providers/recipe_provider.dart';
import 'features/scan/providers/scan_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment configuration.
  await dotenv.load(fileName: '.env');

  // Initialize Firebase.
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: EnvConfig.firebaseApiKey,
      appId: EnvConfig.firebaseAppId,
      messagingSenderId: EnvConfig.firebaseMessagingSenderId,
      projectId: EnvConfig.firebaseProjectId,
    ),
  );

  // Create core services.
  final connectivityService = ConnectivityService();
  final authService = AuthService();

  // Auto sign-in anonymously if no user is signed in.
  if (!authService.isSignedIn) {
    try {
      await authService.signInAnonymously();
      developer.log('Anonymous sign-in succeeded, uid: ${authService.currentUser?.uid}');
    } catch (e) {
      developer.log('Anonymous sign-in failed: $e', error: e);
    }
  }
  developer.log('Auth state: isSignedIn=${authService.isSignedIn}, uid=${authService.currentUser?.uid}');

  final apiClient = ApiClient(authService: authService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectivityService>.value(
            value: connectivityService),
        ChangeNotifierProvider<AuthService>.value(value: authService),
        Provider<ApiClient>.value(value: apiClient),
        ChangeNotifierProvider<RecipeProvider>(
          create: (_) => RecipeProvider(apiClient: apiClient),
        ),
        ChangeNotifierProvider<ScanProvider>(
          create: (_) => ScanProvider(
            apiClient: apiClient,
            authService: authService,
          ),
        ),
      ],
      child: const RatatouilleApp(),
    ),
  );
}
