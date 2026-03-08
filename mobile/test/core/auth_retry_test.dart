import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:ratatouille/core/api_client.dart';

void main() {
  group('ApiClient auth retry', () {
    test('getWithRetry retries on 401 with refreshed token', () async {
      int callCount = 0;
      final mockClient = http_testing.MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('{"detail": "Unauthorized"}', 401);
        }
        return http.Response('{"result": "ok"}', 200);
      });

      int tokenCallCount = 0;
      final client = ApiClient(
        httpClient: mockClient,
        baseUrl: 'http://localhost',
        tokenProvider: () async {
          tokenCallCount++;
          return 'token-$tokenCallCount';
        },
      );

      final result = await client.getWithRetry('/test');
      expect(result['result'], 'ok');
      expect(callCount, 2);
    });

    test('getWithRetry throws on non-401 errors', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response('{"detail": "Not Found"}', 404);
      });

      final client = ApiClient(
        httpClient: mockClient,
        baseUrl: 'http://localhost',
        tokenProvider: () async => 'token',
      );

      expect(
        () => client.getWithRetry('/test'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('postWithRetry retries on 401', () async {
      int callCount = 0;
      final mockClient = http_testing.MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('{"detail": "Unauthorized"}', 401);
        }
        return http.Response(jsonEncode({'id': '123'}), 200);
      });

      final client = ApiClient(
        httpClient: mockClient,
        baseUrl: 'http://localhost',
        tokenProvider: () async => 'token',
      );

      final result = await client.postWithRetry('/test', body: {'name': 'foo'});
      expect(result['id'], '123');
      expect(callCount, 2);
    });
  });
}
