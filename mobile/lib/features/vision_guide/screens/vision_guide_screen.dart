import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

/// Side-by-side visual guide UX.
///
/// Shows the user's camera feed alongside AI-generated visual guidance
/// for the current cooking step.
class VisionGuideScreen extends StatelessWidget {
  final String sessionId;

  const VisionGuideScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual Guide'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.sessionPath(sessionId)),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.compare,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Visual Guide',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Session: $sessionId',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Compare your cooking progress with AI-generated visual references.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.sessionPath(sessionId)),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Session'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
