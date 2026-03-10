import 'package:permission_handler/permission_handler.dart';

/// Result of requesting microphone + camera permissions.
class PermissionResult {
  final bool micGranted;
  final bool cameraGranted;

  const PermissionResult({
    required this.micGranted,
    required this.cameraGranted,
  });

  bool get allGranted => micGranted && cameraGranted;
  bool get micOnly => micGranted && !cameraGranted;
  bool get noneGranted => !micGranted && !cameraGranted;
}

/// Handles runtime permission requests for mic and camera.
class PermissionService {
  /// Request both microphone and camera permissions.
  Future<PermissionResult> requestMicCamera() async {
    final statuses = await [
      Permission.microphone,
      Permission.camera,
    ].request();

    return PermissionResult(
      micGranted: statuses[Permission.microphone]?.isGranted ?? false,
      cameraGranted: statuses[Permission.camera]?.isGranted ?? false,
    );
  }

  /// Check if microphone permission is currently granted.
  Future<bool> isMicGranted() async {
    return (await Permission.microphone.status).isGranted;
  }

  /// Check if camera permission is currently granted.
  Future<bool> isCameraGranted() async {
    return (await Permission.camera.status).isGranted;
  }
}
