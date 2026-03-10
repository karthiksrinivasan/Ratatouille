import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:ratatouille/core/api_client.dart';

/// A minimal fake that provides a token without requiring Firebase.
/// Uses the [tokenProvider] constructor parameter of [ApiClient] instead of
/// extending [AuthService] (which needs Firebase.initializeApp).
class FakeTokenProvider {
  final String? fakeToken;

  FakeTokenProvider({this.fakeToken = 'test-token-123'});

  Future<String?> call() async => fakeToken;
}

void main() {
  group('ApiClient', () {
    late FakeTokenProvider tokenProvider;

    setUp(() {
      tokenProvider = FakeTokenProvider();
    });

    test('GET request sends auth header and parses JSON', () async {
      final mockClient = http_testing.MockClient((request) async {
        // Verify auth header is present.
        expect(
          request.headers['authorization'],
          equals('Bearer test-token-123'),
        );
        expect(request.method, equals('GET'));
        expect(request.url.path, equals('/api/v1/recipes'));

        return http.Response(
          jsonEncode({'recipes': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        tokenProvider: tokenProvider.call,
        httpClient: mockClient,
        baseUrl: 'https://api.test.com',
      );

      final result = await apiClient.get('/api/v1/recipes');
      expect(result, containsPair('recipes', []));

      apiClient.dispose();
    });

    test('POST request sends JSON body', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.headers['content-type'], equals('application/json'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], equals('Test Recipe'));

        return http.Response(
          jsonEncode({'id': 'recipe-1', 'name': 'Test Recipe'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        tokenProvider: tokenProvider.call,
        httpClient: mockClient,
        baseUrl: 'https://api.test.com',
      );

      final result = await apiClient.post(
        '/api/v1/recipes',
        body: {'name': 'Test Recipe'},
      );
      expect(result['id'], equals('recipe-1'));

      apiClient.dispose();
    });

    test('throws ApiException on error response', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Not found'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        tokenProvider: tokenProvider.call,
        httpClient: mockClient,
        baseUrl: 'https://api.test.com',
      );

      expect(
        () => apiClient.get('/api/v1/recipes/missing'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.isNotFound, 'isNotFound', true)
              .having((e) => e.message, 'message', 'Not found'),
        ),
      );

      apiClient.dispose();
    });

    test('handles 401 unauthorized', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Token expired'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        tokenProvider: tokenProvider.call,
        httpClient: mockClient,
        baseUrl: 'https://api.test.com',
      );

      expect(
        () => apiClient.get('/api/v1/me'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isUnauthorized, 'isUnauthorized', true),
        ),
      );

      apiClient.dispose();
    });

    test('sends request without auth when token is null', () async {
      final noTokenProvider = FakeTokenProvider(fakeToken: null);

      final mockClient = http_testing.MockClient((request) async {
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response(jsonEncode({'ok': true}), 200);
      });

      final apiClient = ApiClient(
        tokenProvider: noTokenProvider.call,
        httpClient: mockClient,
        baseUrl: 'https://api.test.com',
      );

      final result = await apiClient.get('/health');
      expect(result['ok'], isTrue);

      apiClient.dispose();
    });

    test('DELETE request works', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, equals('DELETE'));
        return http.Response(jsonEncode({'deleted': true}), 200);
      });

      final apiClient = ApiClient(
        tokenProvider: tokenProvider.call,
        httpClient: mockClient,
        baseUrl: 'https://api.test.com',
      );

      final result = await apiClient.delete('/api/v1/recipes/1');
      expect(result['deleted'], isTrue);

      apiClient.dispose();
    });

    test('PUT request sends JSON body', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.method, equals('PUT'));
        return http.Response(jsonEncode({'updated': true}), 200);
      });

      final apiClient = ApiClient(
        tokenProvider: tokenProvider.call,
        httpClient: mockClient,
        baseUrl: 'https://api.test.com',
      );

      final result = await apiClient.put(
        '/api/v1/recipes/1',
        body: {'name': 'Updated'},
      );
      expect(result['updated'], isTrue);

      apiClient.dispose();
    });

    test('query params are appended to URL', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.url.queryParameters['limit'], equals('10'));
        expect(request.url.queryParameters['offset'], equals('0'));
        return http.Response(jsonEncode({'items': []}), 200);
      });

      final apiClient = ApiClient(
        tokenProvider: tokenProvider.call,
        httpClient: mockClient,
        baseUrl: 'https://api.test.com',
      );

      await apiClient.get(
        '/api/v1/recipes',
        queryParams: {'limit': '10', 'offset': '0'},
      );

      apiClient.dispose();
    });

    test('GET times out after default timeout', () async {
      final client = http_testing.MockClient((request) async {
        await Future.delayed(const Duration(seconds: 15));
        return http.Response('{}', 200);
      });

      final api = ApiClient(
        httpClient: client,
        baseUrl: 'http://test',
      );

      expect(
        () => api.get('/v1/health'),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
