import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

/// Post-session completion and wind-down screen.
///
/// Shows a summary of the cooking session, tips for improvement,
/// and options to save or share the result.
class PostSessionScreen extends StatelessWidget {
  final String sessionId;

  const PostSessionScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Complete'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.celebration,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Great job!',
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
                'Your cooking session is complete. Review your results and save your progress.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => context.go(AppRoutes.scan),
                icon: const Icon(Icons.home),
                label: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
