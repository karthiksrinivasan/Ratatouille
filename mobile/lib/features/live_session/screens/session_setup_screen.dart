import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../core/api_client.dart';
import '../../../core/session_api.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/widgets/error_display.dart';

/// Session setup screen — bridge between recipe selection and live session.
///
/// Shows recipe summary, phone setup options, ambient opt-in,
/// and handles activation with error recovery.
class SessionSetupScreen extends StatefulWidget {
  final String sessionId;
  final String? recipeTitle;

  const SessionSetupScreen({
    super.key,
    required this.sessionId,
    this.recipeTitle,
  });

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  bool _ambientEnabled = true;
  bool _activating = false;
  String? _error;

  Future<void> _activate() async {
    setState(() {
      _activating = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final sessionApi = SessionApiService(api: api);
      final response = await sessionApi.activate(widget.sessionId);

      if (mounted && response.status == 'active') {
        context.go(AppRoutes.sessionPath(widget.sessionId));
      } else if (mounted) {
        setState(() => _error = 'Session could not be activated. Try again.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Activation failed: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _activating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Setup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Recipe summary
            _buildRecipeSummary(theme),
            const SizedBox(height: Spacing.lg),

            // Phone setup instructions
            _buildSetupInstructions(theme),
            const SizedBox(height: Spacing.lg),

            // Ambient opt-in
            _buildAmbientOption(theme),
            const SizedBox(height: Spacing.lg),

            // Error state
            if (_error != null) ...[
              ErrorDisplay(
                message: _error!,
                onRetry: _activate,
              ),
              const SizedBox(height: Spacing.md),
            ],

            // Activate button
            SizedBox(
              height: TouchTargets.handsBusy,
              child: FilledButton.icon(
                onPressed: _activating ? null : _activate,
                icon: _activating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_activating ? 'Activating...' : 'Start Cooking'),
              ),
            ),

            const SizedBox(height: Spacing.md),

            // Back path
            OutlinedButton(
              onPressed: _activating ? null : () => context.pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeSummary(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.restaurant_menu,
                    color: theme.colorScheme.primary),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    widget.recipeTitle ?? 'Selected Recipe',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Session ID: ${widget.sessionId}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupInstructions(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phone Setup',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.sm),
            _setupStep(Icons.volume_up, 'Turn up volume for voice guidance',
                theme),
            const SizedBox(height: Spacing.sm),
            _setupStep(Icons.screen_lock_portrait,
                'Keep screen on during cooking', theme),
            const SizedBox(height: Spacing.sm),
            _setupStep(Icons.phone_android,
                'Place phone where you can see it', theme),
          ],
        ),
      ),
    );
  }

  Widget _setupStep(IconData icon, String text, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(text, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }

  Widget _buildAmbientOption(ThemeData theme) {
    return Card(
      child: SwitchListTile(
        title: const Text('Ambient Listening'),
        subtitle: const Text(
            'AI listens for cooking sounds and proactively helps'),
        value: _ambientEnabled,
        onChanged: (v) => setState(() => _ambientEnabled = v),
        secondary: Icon(
          _ambientEnabled ? Icons.hearing : Icons.hearing_disabled,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
