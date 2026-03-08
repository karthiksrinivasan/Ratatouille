import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Set up Firebase Core + Auth mocks so that Firebase.initializeApp() and
/// FirebaseAuth.instance work in tests without real Firebase.
Future<void> setupFirebaseMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final binding = TestDefaultBinaryMessengerBinding.instance;

  // Mock Firebase Core
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_core'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'Firebase#initializeCore') {
        return [
          {
            'name': '[DEFAULT]',
            'options': {
              'apiKey': 'test-api-key',
              'appId': 'test-app-id',
              'messagingSenderId': 'test-sender-id',
              'projectId': 'test-project-id',
            },
            'pluginConstants': <String, String>{},
          }
        ];
      }
      if (methodCall.method == 'Firebase#initializeApp') {
        return {
          'name': methodCall.arguments['appName'] ?? '[DEFAULT]',
          'options': methodCall.arguments['options'] ??
              <String, String>{},
          'pluginConstants': <String, String>{},
        };
      }
      return null;
    },
  );

  // Mock Firebase Auth
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_auth'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'Auth#registerIdTokenListener' ||
          methodCall.method == 'Auth#registerAuthStateListener') {
        return <String, dynamic>{'user': null};
      }
      return null;
    },
  );

  // Initialize Firebase with mocks
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'test-api-key',
      appId: 'test-app-id',
      messagingSenderId: 'test-sender-id',
      projectId: 'test-project-id',
    ),
  );
}
