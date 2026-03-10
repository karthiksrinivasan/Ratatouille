import 'package:flutter_test/flutter_test.dart';
import 'package:ratatouille/core/connectivity.dart';

void main() {
  group('ConnectivityService', () {
    late ConnectivityService service;

    setUp(() {
      // Use autoListen: false to avoid platform channel calls in tests.
      service = ConnectivityService(autoListen: false);
    });

    tearDown(() {
      service.dispose();
    });

    test('initial state is online', () {
      expect(service.status, ConnectivityStatus.online);
      expect(service.isOnline, isTrue);
      expect(service.isOffline, isFalse);
    });

    test('markDegraded changes status', () {
      service.markDegraded();
      expect(service.status, ConnectivityStatus.degraded);
      expect(service.isOnline, isTrue); // isOnline tracks real connectivity
      expect(service.isOffline, isFalse);
    });

    test('markOffline changes status', () {
      service.markOffline();
      expect(service.status, ConnectivityStatus.offline);
      expect(service.isOffline, isTrue);
    });

    test('markOnline resets from offline', () {
      service.markOffline();
      service.markOnline();
      expect(service.isOnline, isTrue);
    });

    test('onRequestSuccess resets to online', () {
      service.markDegraded();
      service.onRequestSuccess();
      expect(service.isOnline, isTrue);
    });

    test('onRequestFailure transitions online to degraded', () {
      service.onRequestFailure();
      expect(service.status, ConnectivityStatus.degraded);
    });

    test('onRequestFailure transitions degraded to offline', () {
      service.markDegraded();
      service.onRequestFailure();
      expect(service.status, ConnectivityStatus.offline);
    });

    test('notifies listeners on state changes', () {
      int notifyCount = 0;
      service.addListener(() => notifyCount++);

      service.markDegraded();
      expect(notifyCount, 1);

      service.markOffline();
      expect(notifyCount, 2);

      service.markOnline();
      expect(notifyCount, 3);
    });

    test('does not notify when state unchanged', () {
      int notifyCount = 0;
      service.addListener(() => notifyCount++);

      service.markOnline(); // already online
      expect(notifyCount, 0);
    });

    test('ConnectivityService exposes an onStatusChange stream getter', () {
      // We just verify the getter exists — actual stream requires platform.
      expect(service.onStatusChange, isA<Stream<bool>>());
    });
  });
}
