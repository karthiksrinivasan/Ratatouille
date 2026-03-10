import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/permission_service.dart';

void main() {
  test('PermissionService has requestMicCamera method', () {
    final service = PermissionService();
    expect(service.requestMicCamera, isA<Function>());
  });

  test('PermissionResult correctly reports allGranted', () {
    const result = PermissionResult(micGranted: true, cameraGranted: true);
    expect(result.allGranted, isTrue);
    expect(result.micOnly, isFalse);
    expect(result.noneGranted, isFalse);
  });

  test('PermissionResult correctly reports micOnly', () {
    const result = PermissionResult(micGranted: true, cameraGranted: false);
    expect(result.allGranted, isFalse);
    expect(result.micOnly, isTrue);
    expect(result.noneGranted, isFalse);
  });

  test('PermissionResult correctly reports noneGranted', () {
    const result = PermissionResult(micGranted: false, cameraGranted: false);
    expect(result.allGranted, isFalse);
    expect(result.micOnly, isFalse);
    expect(result.noneGranted, isTrue);
  });
}
