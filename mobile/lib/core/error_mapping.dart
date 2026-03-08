import 'dart:io';

import 'api_client.dart';

/// User-friendly error categories.
enum ErrorCategory { network, auth, server, validation, unknown }

/// Maps exceptions to user-friendly error messages.
class ErrorMapping {
  ErrorMapping._();

  static ErrorCategory categorize(dynamic error) {
    if (error is ApiException) {
      if (error.isUnauthorized || error.isForbidden) return ErrorCategory.auth;
      if (error.isServerError) return ErrorCategory.server;
      if (error.statusCode == 422) return ErrorCategory.validation;
      return ErrorCategory.unknown;
    }
    if (error is SocketException || error is HttpException) {
      return ErrorCategory.network;
    }
    return ErrorCategory.unknown;
  }

  static String userMessage(dynamic error) {
    final category = categorize(error);
    switch (category) {
      case ErrorCategory.network:
        return 'Unable to connect. Check your internet and try again.';
      case ErrorCategory.auth:
        return 'Please sign in again to continue.';
      case ErrorCategory.server:
        return 'Something went wrong on our end. Please try again.';
      case ErrorCategory.validation:
        if (error is ApiException) {
          return error.message;
        }
        return 'Invalid input. Please check and try again.';
      case ErrorCategory.unknown:
        return 'Something unexpected happened. Please try again.';
    }
  }
}
