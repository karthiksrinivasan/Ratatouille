import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';

/// Manages camera preview for live cooking sessions.
///
/// Supports front/back camera switching and frame capture for
/// vision checks and ambient mode.
class CameraService {
  CameraController? _controller;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  CameraController? get controller => _controller;

  /// Initialize the camera.
  ///
  /// [front] selects front-facing camera if true, back-facing otherwise.
  Future<void> initialize({bool front = false}) async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final camera = front
        ? cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => cameras.first,
          )
        : cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );
    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller!.initialize();
    _initialized = true;
  }

  /// Flip between front and back camera.
  Future<void> flipCamera() async {
    if (_controller == null) return;
    final current = _controller!.description.lensDirection;
    await dispose();
    await initialize(front: current == CameraLensDirection.back);
  }

  /// Capture a single frame as base64-encoded JPEG.
  Future<String?> captureFrame() async {
    if (_controller == null || !_initialized) return null;
    final file = await _controller!.takePicture();
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  /// Capture a single frame and return the file path.
  Future<String?> captureFrameToFile() async {
    if (_controller == null || !_initialized) return null;
    final file = await _controller!.takePicture();
    return file.path;
  }

  /// Release camera resources.
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    _initialized = false;
  }
}
