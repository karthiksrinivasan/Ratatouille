import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/connectivity.dart';

/// Global banner that shows connectivity status when degraded or offline.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, connectivity, _) {
        if (connectivity.isOnline) return const SizedBox.shrink();

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
              onPressed: connectivity.markOnline,
              child: const Text('Dismiss'),
            ),
          ],
        );
      },
    );
  }
}
