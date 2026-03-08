import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'app/app.dart';
import 'app/router.dart';
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
  final apiClient = ApiClient(authService: authService);
  final router = createRouter(authService);

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
      child: RatatouilleApp(router: router),
    ),
  );
}
