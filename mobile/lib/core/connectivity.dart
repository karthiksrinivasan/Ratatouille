import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Network connectivity state for the app.
enum ConnectivityStatus { online, degraded, offline }

/// Tracks network connectivity using connectivity_plus and exposes it
/// to the widget tree via [ChangeNotifier].
class ConnectivityService extends ChangeNotifier {
  Connectivity? _connectivity;
  StreamSubscription<ConnectivityResult>? _sub;
  Timer? _degradedTimer;

  ConnectivityStatus _status = ConnectivityStatus.online;
  bool _isOnline = true;

  ConnectivityStatus get status => _status;
  bool get isOnline => _isOnline;
  bool get isOffline => _status == ConnectivityStatus.offline;

  /// Create a connectivity service.
  /// Pass [autoListen] = false for unit tests that lack platform channels.
  ConnectivityService({bool autoListen = true}) {
    if (autoListen) {
      _connectivity = Connectivity();
      _startListening();
    }
  }

  void _startListening() {
    _sub = _connectivity!.onConnectivityChanged.listen((result) {
      final online = result != ConnectivityResult.none;
      if (online != _isOnline) {
        _isOnline = online;
        if (online) {
          markOnline();
        } else {
          markOffline();
        }
      }
    });
  }

  /// Stream of connectivity changes (true = online, false = offline).
  Stream<bool> get onStatusChange {
    _connectivity ??= Connectivity();
    return _connectivity!.onConnectivityChanged
        .map((result) => result != ConnectivityResult.none);
  }

  /// Check connectivity right now.
  Future<bool> checkNow() async {
    _connectivity ??= Connectivity();
    final result = await _connectivity!.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;
    return _isOnline;
  }

  /// Mark connectivity as online.
  void markOnline() {
    _degradedTimer?.cancel();
    if (_status != ConnectivityStatus.online) {
      _status = ConnectivityStatus.online;
      _isOnline = true;
      notifyListeners();
    }
  }

  /// Mark connectivity as degraded (e.g. slow responses, WS reconnecting).
  void markDegraded() {
    if (_status != ConnectivityStatus.degraded) {
      _status = ConnectivityStatus.degraded;
      notifyListeners();
    }
  }

  /// Mark connectivity as offline.
  void markOffline() {
    if (_status != ConnectivityStatus.offline) {
      _status = ConnectivityStatus.offline;
      _isOnline = false;
      notifyListeners();
    }
  }

  /// Record a successful request — resets to online.
  void onRequestSuccess() => markOnline();

  /// Record a failed request — sets degraded, then offline after timeout.
  void onRequestFailure() {
    if (_status == ConnectivityStatus.online) {
      markDegraded();
      _degradedTimer?.cancel();
      _degradedTimer = Timer(const Duration(seconds: 5), () {
        if (_status == ConnectivityStatus.degraded) {
          markOffline();
        }
      });
    } else if (_status == ConnectivityStatus.degraded) {
      markOffline();
    }
  }

  @override
  void dispose() {
    _degradedTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
