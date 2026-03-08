import 'package:flutter/material.dart';

import 'connectivity_banner.dart';

/// Wraps a child widget with a connectivity banner that appears at the top
/// when the network state is degraded or offline.
class ConnectivityWrapper extends StatelessWidget {
  final Widget child;

  const ConnectivityWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ConnectivityBanner(),
        Expanded(child: child),
      ],
    );
  }
}
