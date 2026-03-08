import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

/// Live cooking session screen with real-time AI guidance.
///
/// Connects to the backend via WebSocket for step-by-step cooking
/// instructions, timers, and voice interaction.
class LiveSessionScreen extends StatelessWidget {
  final String sessionId;

  const LiveSessionScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cooking Session'),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: 'Visual Guide',
            onPressed: () => context.go(AppRoutes.visionGuidePath(sessionId)),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.soup_kitchen,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Live Cooking',
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
                'Follow along with AI-guided cooking instructions in real time.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () =>
                    context.go(AppRoutes.postSessionPath(sessionId)),
                icon: const Icon(Icons.check_circle),
                label: const Text('Finish Session'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
