import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  // In dev mode, connect to the Firebase Auth Emulator to bypass
  // reCAPTCHA Enterprise (which blocks email/password sign-up on
  // emulators and devices without proper SHA fingerprint config).
  // Set USE_AUTH_EMULATOR=true in .env to enable.
  //
  // Requires: firebase emulators:start --only auth
  final useEmulator = dotenv.get('USE_AUTH_EMULATOR', fallback: 'false').toLowerCase() == 'true';
  if (useEmulator) {
    // 10.0.2.2 is the host machine from an Android emulator.
    // Use 'localhost' if running on a real device with adb reverse.
    final emulatorHost = dotenv.get('AUTH_EMULATOR_HOST', fallback: '10.0.2.2');
    final emulatorPort = int.parse(dotenv.get('AUTH_EMULATOR_PORT', fallback: '9099'));
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, emulatorPort);
    developer.log('Firebase Auth: using emulator at $emulatorHost:$emulatorPort');
  } else if (kDebugMode || EnvConfig.isDev) {
    // This only helps with phone auth verification, not email/password reCAPTCHA.
    // For email/password, either use the auth emulator (above) or disable
    // reCAPTCHA Enterprise in Firebase Console > Authentication > Settings.
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: true,
    );
    developer.log('Firebase Auth: app verification disabled for testing');
  }

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
