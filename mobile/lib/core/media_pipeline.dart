import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';
import 'auth_service.dart';

/// Constraints for media capture.
class CaptureConstraints {
  static const int minPhotos = 2;
  static const int maxPhotos = 6;
  static const Duration minVideoLength = Duration(seconds: 3);
  static const Duration maxVideoLength = Duration(seconds: 10);
  static const double maxImageSizeMB = 10.0;
}

/// Upload state for tracking progress.
enum UploadState { idle, uploading, success, error, cancelled }

/// Manages media capture (photos, video, frames) and upload pipeline.
class MediaPipeline extends ChangeNotifier {
  final ImagePicker _picker;
  final ApiClient _apiClient;
  UploadState _uploadState = UploadState.idle;
  double _uploadProgress = 0.0;
  String? _uploadError;
  bool _cancelled = false;

  MediaPipeline({
    ImagePicker? picker,
    required ApiClient apiClient,
    AuthService? authService,
  })  : _picker = picker ?? ImagePicker(),
        _apiClient = apiClient;

  UploadState get uploadState => _uploadState;
  double get uploadProgress => _uploadProgress;
  String? get uploadError => _uploadError;
  bool get isUploading => _uploadState == UploadState.uploading;

  /// Capture a photo from camera.
  Future<File?> capturePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Pick a photo from gallery.
  Future<File?> pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Capture a short video (3-10 seconds) for scan mode.
  Future<File?> captureVideo() async {
    final picked = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: CaptureConstraints.maxVideoLength,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Capture a single frame for vision-check (uses camera photo).
  Future<File?> captureFrame() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1280,
      maxHeight: 720,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// Validate image files meet constraints.
  String? validateImages(List<File> images) {
    if (images.length < CaptureConstraints.minPhotos) {
      return 'At least ${CaptureConstraints.minPhotos} photos required';
    }
    if (images.length > CaptureConstraints.maxPhotos) {
      return 'Maximum ${CaptureConstraints.maxPhotos} photos allowed';
    }
    for (final img in images) {
      final sizeMB = img.lengthSync() / (1024 * 1024);
      if (sizeMB > CaptureConstraints.maxImageSizeMB) {
        return 'Image too large (max ${CaptureConstraints.maxImageSizeMB}MB)';
      }
    }
    return null;
  }

  /// Upload a file with progress tracking.
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    String fieldName = 'file',
    Map<String, String>? extraFields,
  }) async {
    _cancelled = false;
    _setUploadState(UploadState.uploading);
    _uploadProgress = 0.0;
    _uploadError = null;
    notifyListeners();

    try {
      // Simulate progress for standard upload (http package doesn't support
      // stream progress natively — this provides UX feedback).
      _uploadProgress = 0.3;
      notifyListeners();

      if (_cancelled) {
        _setUploadState(UploadState.cancelled);
        throw Exception('Upload cancelled');
      }

      final result = await _apiClient.uploadFile(
        path,
        filePath: filePath,
        fieldName: fieldName,
        extraFields: extraFields,
      );

      _uploadProgress = 1.0;
      _setUploadState(UploadState.success);
      return result;
    } catch (e) {
      if (!_cancelled) {
        _uploadError = e.toString();
        _setUploadState(UploadState.error);
      }
      rethrow;
    }
  }

  /// Cancel an in-progress upload.
  void cancelUpload() {
    if (_uploadState == UploadState.uploading) {
      _cancelled = true;
      _setUploadState(UploadState.cancelled);
    }
  }

  /// Reset upload state.
  void resetUpload() {
    _uploadState = UploadState.idle;
    _uploadProgress = 0.0;
    _uploadError = null;
    _cancelled = false;
    notifyListeners();
  }

  void _setUploadState(UploadState state) {
    _uploadState = state;
    notifyListeners();
  }
}
