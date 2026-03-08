import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supported application environments.
enum AppEnvironment { dev, staging, prod }

/// Centralized environment configuration.
///
/// All values are read from the `.env` file loaded at app startup via
/// `flutter_dotenv`.  No URLs or project IDs are hardcoded.
class EnvConfig {
  EnvConfig._();

  // ---------------------------------------------------------------------------
  // Backend
  // ---------------------------------------------------------------------------

  /// Base URL of the FastAPI backend (no trailing slash).
  static String get backendUrl =>
      _require('BACKEND_URL');

  /// WebSocket URL derived from the backend URL.
  /// Replaces http(s) with ws(s).
  static String get wsUrl {
    final url = backendUrl;
    if (url.startsWith('https')) {
      return url.replaceFirst('https', 'wss');
    }
    return url.replaceFirst('http', 'ws');
  }

  // ---------------------------------------------------------------------------
  // Firebase
  // ---------------------------------------------------------------------------

  static String get firebaseProjectId =>
      _require('FIREBASE_PROJECT_ID');

  static String get firebaseApiKey =>
      _require('FIREBASE_API_KEY');

  static String get firebaseAppId =>
      _require('FIREBASE_APP_ID');

  static String get firebaseMessagingSenderId =>
      _require('FIREBASE_MESSAGING_SENDER_ID');

  // ---------------------------------------------------------------------------
  // App environment
  // ---------------------------------------------------------------------------

  static AppEnvironment get environment {
    final value = dotenv.get('APP_ENV', fallback: 'dev').toLowerCase();
    switch (value) {
      case 'prod':
      case 'production':
        return AppEnvironment.prod;
      case 'staging':
        return AppEnvironment.staging;
      default:
        return AppEnvironment.dev;
    }
  }

  static bool get isDev => environment == AppEnvironment.dev;
  static bool get isStaging => environment == AppEnvironment.staging;
  static bool get isProd => environment == AppEnvironment.prod;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Return the env var or throw a clear error if missing.
  static String _require(String key) {
    final value = dotenv.maybeGet(key);
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing required environment variable: $key. '
        'Add it to your .env file (see .env.example).',
      );
    }
    return value;
  }
}
