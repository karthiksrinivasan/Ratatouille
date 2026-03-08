import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ratatouille/core/env_config.dart';

void main() {
  group('EnvConfig', () {
    setUp(() {
      // Load a test environment string into dotenv.
      dotenv.testLoad(fileInput: '''
BACKEND_URL=https://test-api.example.com
FIREBASE_PROJECT_ID=test-project-123
FIREBASE_API_KEY=test-api-key
FIREBASE_APP_ID=1:123:android:abc
FIREBASE_MESSAGING_SENDER_ID=123456
APP_ENV=dev
''');
    });

    test('reads backend URL from env', () {
      expect(EnvConfig.backendUrl, equals('https://test-api.example.com'));
    });

    test('derives wss URL from https backend URL', () {
      expect(EnvConfig.wsUrl, equals('wss://test-api.example.com'));
    });

    test('reads Firebase project ID', () {
      expect(EnvConfig.firebaseProjectId, equals('test-project-123'));
    });

    test('reads Firebase API key', () {
      expect(EnvConfig.firebaseApiKey, equals('test-api-key'));
    });

    test('reads Firebase app ID', () {
      expect(EnvConfig.firebaseAppId, equals('1:123:android:abc'));
    });

    test('reads Firebase messaging sender ID', () {
      expect(EnvConfig.firebaseMessagingSenderId, equals('123456'));
    });

    test('parses dev environment', () {
      expect(EnvConfig.environment, equals(AppEnvironment.dev));
      expect(EnvConfig.isDev, isTrue);
      expect(EnvConfig.isStaging, isFalse);
      expect(EnvConfig.isProd, isFalse);
    });

    test('parses staging environment', () {
      dotenv.testLoad(fileInput: '''
BACKEND_URL=https://staging.example.com
FIREBASE_PROJECT_ID=p
FIREBASE_API_KEY=k
FIREBASE_APP_ID=a
FIREBASE_MESSAGING_SENDER_ID=1
APP_ENV=staging
''');
      expect(EnvConfig.environment, equals(AppEnvironment.staging));
      expect(EnvConfig.isStaging, isTrue);
    });

    test('parses prod environment', () {
      dotenv.testLoad(fileInput: '''
BACKEND_URL=https://prod.example.com
FIREBASE_PROJECT_ID=p
FIREBASE_API_KEY=k
FIREBASE_APP_ID=a
FIREBASE_MESSAGING_SENDER_ID=1
APP_ENV=prod
''');
      expect(EnvConfig.environment, equals(AppEnvironment.prod));
      expect(EnvConfig.isProd, isTrue);
    });

    test('derives ws URL from http backend URL', () {
      dotenv.testLoad(fileInput: '''
BACKEND_URL=http://localhost:8000
FIREBASE_PROJECT_ID=p
FIREBASE_API_KEY=k
FIREBASE_APP_ID=a
FIREBASE_MESSAGING_SENDER_ID=1
APP_ENV=dev
''');
      expect(EnvConfig.wsUrl, equals('ws://localhost:8000'));
    });

    test('throws on missing required variable', () {
      dotenv.testLoad(fileInput: 'APP_ENV=dev\n');
      expect(
        () => EnvConfig.backendUrl,
        throwsA(isA<StateError>()),
      );
    });
  });
}
