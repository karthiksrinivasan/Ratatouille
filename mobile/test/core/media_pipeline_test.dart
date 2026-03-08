import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:ratatouille/core/api_client.dart';
import 'package:ratatouille/core/media_pipeline.dart';

void main() {
  group('CaptureConstraints', () {
    test('min photos is 2', () {
      expect(CaptureConstraints.minPhotos, 2);
    });

    test('max photos is 6', () {
      expect(CaptureConstraints.maxPhotos, 6);
    });

    test('video length range is 3-10 seconds', () {
      expect(CaptureConstraints.minVideoLength.inSeconds, 3);
      expect(CaptureConstraints.maxVideoLength.inSeconds, 10);
    });
  });

  group('MediaPipeline', () {
    late ApiClient apiClient;
    late MediaPipeline pipeline;

    setUp(() {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response('{"status": "ok"}', 200);
      });
      apiClient = ApiClient(
        httpClient: mockClient,
        baseUrl: 'http://localhost',
        tokenProvider: () async => 'test-token',
      );
      pipeline = MediaPipeline(apiClient: apiClient);
    });

    test('validateImages rejects too few images', () {
      final result = pipeline.validateImages([File('a.jpg')]);
      expect(result, contains('At least 2'));
    });

    test('validateImages returns null for empty list error', () {
      final result = pipeline.validateImages([]);
      expect(result, isNotNull);
    });

    test('initial upload state is idle', () {
      expect(pipeline.uploadState, UploadState.idle);
      expect(pipeline.isUploading, isFalse);
      expect(pipeline.uploadProgress, 0.0);
    });

    test('resetUpload restores idle state', () {
      pipeline.resetUpload();
      expect(pipeline.uploadState, UploadState.idle);
      expect(pipeline.uploadProgress, 0.0);
      expect(pipeline.uploadError, isNull);
    });

    test('UploadState has all expected values', () {
      expect(UploadState.values, containsAll([
        UploadState.idle,
        UploadState.uploading,
        UploadState.success,
        UploadState.error,
        UploadState.cancelled,
      ]));
    });
  });
}
