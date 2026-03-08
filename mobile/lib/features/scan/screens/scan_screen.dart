import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

/// Fridge/pantry scan flow — the app's home screen.
///
/// Users capture photos of their fridge or pantry, which are sent to the
/// backend for ingredient detection via Gemini vision.
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ratatouille'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.camera_alt_outlined,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Scan Your Kitchen',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Take a photo of your fridge or pantry and let AI identify your ingredients.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: Launch camera / image picker
                },
                icon: const Icon(Icons.photo_camera),
                label: const Text('Take Photo'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.go(AppRoutes.suggestions),
                icon: const Icon(Icons.restaurant_menu),
                label: const Text('View Suggestions'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
