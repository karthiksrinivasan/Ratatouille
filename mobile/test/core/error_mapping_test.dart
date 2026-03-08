import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/core/error_mapping.dart';

void main() {
  group('ErrorMapping', () {
    test('categorizes 401 as auth', () {
      final error = ApiException(statusCode: 401, message: 'Unauthorized');
      expect(ErrorMapping.categorize(error), ErrorCategory.auth);
    });

    test('categorizes 403 as auth', () {
      final error = ApiException(statusCode: 403, message: 'Forbidden');
      expect(ErrorMapping.categorize(error), ErrorCategory.auth);
    });

    test('categorizes 500 as server', () {
      final error = ApiException(statusCode: 500, message: 'Server error');
      expect(ErrorMapping.categorize(error), ErrorCategory.server);
    });

    test('categorizes 422 as validation', () {
      final error = ApiException(statusCode: 422, message: 'Bad input');
      expect(ErrorMapping.categorize(error), ErrorCategory.validation);
    });

    test('categorizes SocketException as network', () {
      final error = const SocketException('Connection refused');
      expect(ErrorMapping.categorize(error), ErrorCategory.network);
    });

    test('categorizes unknown exceptions', () {
      expect(ErrorMapping.categorize(Exception('???')), ErrorCategory.unknown);
    });

    test('userMessage returns friendly message for network error', () {
      final msg = ErrorMapping.userMessage(const SocketException('fail'));
      expect(msg, contains('internet'));
    });

    test('userMessage returns friendly message for auth error', () {
      final msg = ErrorMapping.userMessage(
        const ApiException(statusCode: 401, message: 'Unauthorized'),
      );
      expect(msg, contains('sign in'));
    });

    test('userMessage returns validation detail for 422', () {
      final msg = ErrorMapping.userMessage(
        const ApiException(statusCode: 422, message: 'Title is required'),
      );
      expect(msg, 'Title is required');
    });
  });
}
