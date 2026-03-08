import 'dart:async';

import 'package:flutter/foundation.dart';

/// Network connectivity state for the app.
enum ConnectivityStatus { online, degraded, offline }

/// Tracks network connectivity and exposes it to the widget tree.
class ConnectivityService extends ChangeNotifier {
  ConnectivityStatus _status = ConnectivityStatus.online;
  Timer? _degradedTimer;

  ConnectivityStatus get status => _status;
  bool get isOnline => _status == ConnectivityStatus.online;
  bool get isOffline => _status == ConnectivityStatus.offline;

  /// Mark connectivity as online.
  void markOnline() {
    _degradedTimer?.cancel();
    if (_status != ConnectivityStatus.online) {
      _status = ConnectivityStatus.online;
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
    super.dispose();
  }
}
