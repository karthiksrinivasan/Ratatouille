import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connectivity.dart';

/// Global banner that shows connectivity status when degraded or offline.
///
/// D8.16: Dismissal persists for the current session — once the user
/// taps "Dismiss", the banner stays hidden until connectivity status
/// changes again (e.g. goes offline then back online).
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  /// Session-scoped dismiss state — resets when connectivity changes.
  final ValueNotifier<bool> _dismissed = ValueNotifier<bool>(false);

  /// Track the last status so we can detect transitions and un-dismiss.
  ConnectivityStatus? _lastStatus;

  @override
  void dispose() {
    _dismissed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, connectivity, _) {
        if (connectivity.isOnline) {
          // Reset dismiss state when we come back online
          _dismissed.value = false;
          _lastStatus = ConnectivityStatus.online;
          return const SizedBox.shrink();
        }

        // If status changed (e.g. degraded -> offline), un-dismiss
        if (_lastStatus != null && _lastStatus != connectivity.status) {
          _dismissed.value = false;
        }
        _lastStatus = connectivity.status;

        return ValueListenableBuilder<bool>(
          valueListenable: _dismissed,
          builder: (context, isDismissed, _) {
            if (isDismissed) return const SizedBox.shrink();

            final isOffline = connectivity.isOffline;
            return MaterialBanner(
              content: Text(
                isOffline
                    ? 'No internet connection'
                    : 'Connection is unstable',
              ),
              leading: Icon(
                isOffline ? Icons.cloud_off : Icons.cloud_queue,
                color: isOffline
                    ? Theme.of(context).colorScheme.error
                    : Colors.orange,
              ),
              backgroundColor: isOffline
                  ? Theme.of(context).colorScheme.errorContainer
                  : Colors.orange.shade50,
              actions: [
                TextButton(
                  onPressed: () => _dismissed.value = true,
                  child: const Text('Dismiss'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
