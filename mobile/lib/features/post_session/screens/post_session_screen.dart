import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../core/api_client.dart';
import '../../../core/session_api.dart';
import '../../../shared/design_tokens.dart';

/// Post-session completion, wind-down, and memory confirmation screen.
class PostSessionScreen extends StatefulWidget {
  final String sessionId;

  const PostSessionScreen({super.key, required this.sessionId});

  @override
  State<PostSessionScreen> createState() => _PostSessionScreenState();
}

class _PostSessionScreenState extends State<PostSessionScreen> {
  bool _completing = false;
  bool _completed = false;
  bool _memoryConfirmed = false;
  bool _showMemoryPrompt = false;
  CompleteResponse? _summary;
  String? _error;

  Future<void> _completeSession() async {
    setState(() {
      _completing = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final sessionApi = SessionApiService(api: api);
      final response = await sessionApi.complete(widget.sessionId);

      setState(() {
        _completed = true;
        _summary = response;
        _showMemoryPrompt = true;
      });
    } catch (e) {
      setState(() => _error = 'Could not complete session: $e');
    } finally {
      setState(() => _completing = false);
    }
  }

  Future<void> _confirmMemory() async {
    setState(() {
      _memoryConfirmed = true;
      _showMemoryPrompt = false;
    });

    // Persist memory confirmation to backend
    try {
      final api = context.read<ApiClient>();
      final sessionApi = SessionApiService(api: api);
      // Extract observations from summary if available
      final observations = <String>[];
      if (_summary?.summary != null) {
        final summaryMap = _summary!.summary!;
        if (summaryMap['observations'] is List) {
          observations.addAll(
            (summaryMap['observations'] as List).cast<String>(),
          );
        }
      }
      // Default observation when none extracted from summary
      if (observations.isEmpty) {
        observations.add('User completed session ${widget.sessionId}');
      }
      await sessionApi.saveMemory(
        widget.sessionId,
        confirmed: true,
        observations: observations,
      );
    } catch (_) {
      // Memory save is best-effort — don't block the user
    }
  }

  Future<void> _declineMemory() async {
    setState(() {
      _memoryConfirmed = false;
      _showMemoryPrompt = false;
    });

    // Notify backend that memory was declined
    try {
      final api = context.read<ApiClient>();
      final sessionApi = SessionApiService(api: api);
      await sessionApi.saveMemory(
        widget.sessionId,
        confirmed: false,
      );
    } catch (_) {
      // Best-effort
    }
  }

  @override
  void initState() {
    super.initState();
    // Auto-complete on screen entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _completeSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Complete'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Spacing.lg),

              // Completion beat
              if (!_completed && _completing)
                _buildCompletingState(theme)
              else if (_completed) ...[
                _buildCelebration(theme),
                const SizedBox(height: Spacing.lg),

                // Session summary
                if (_summary?.summary != null) ...[
                  _buildSummaryCard(theme),
                  const SizedBox(height: Spacing.lg),
                ],

                // Memory confirmation gate
                if (_showMemoryPrompt)
                  _buildMemoryPrompt(theme)
                else if (_memoryConfirmed)
                  _buildMemoryConfirmed(theme)
                else
                  _buildMemoryDeclined(theme),

                const SizedBox(height: Spacing.xl),

                // Navigation
                ElevatedButton.icon(
                  onPressed: () => context.go(AppRoutes.home),
                  icon: const Icon(Icons.home),
                  label: const Text('Back to Home'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                OutlinedButton.icon(
                  onPressed: () => context.go(AppRoutes.scan),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cook Something Else'),
                ),
              ],

              // Error state
              if (_error != null) ...[
                const SizedBox(height: Spacing.md),
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(Spacing.cardPadding),
                    child: Column(
                      children: [
                        Text(_error!,
                            style: TextStyle(
                                color: theme.colorScheme.onErrorContainer)),
                        const SizedBox(height: Spacing.sm),
                        TextButton(
                          onPressed: _completeSession,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletingState(ThemeData theme) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: Spacing.xxl),
          CircularProgressIndicator(color: theme.colorScheme.primary),
          const SizedBox(height: Spacing.lg),
          Text('Wrapping up your session...',
              style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildCelebration(ThemeData theme) {
    return Column(
      children: [
        Icon(Icons.celebration, size: 80, color: theme.colorScheme.primary),
        const SizedBox(height: Spacing.md),
        Text('Great job!', style: theme.textTheme.headlineMedium),
        const SizedBox(height: Spacing.sm),
        Text(
          'Your cooking session is complete.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSummaryCard(ThemeData theme) {
    final summary = _summary!.summary!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session Summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (summary['steps_completed'] != null)
              _summaryRow(Icons.check_circle, 'Steps completed',
                  '${summary['steps_completed']}', theme),
            if (summary['total_time_min'] != null)
              _summaryRow(Icons.timer, 'Total time',
                  '${summary['total_time_min']} min', theme),
            if (summary['processes_managed'] != null)
              _summaryRow(Icons.auto_fix_high, 'Processes managed',
                  '${summary['processes_managed']}', theme),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
      IconData icon, String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: Spacing.sm),
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildMemoryPrompt(ThemeData theme) {
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology, color: theme.colorScheme.primary),
                const SizedBox(width: Spacing.sm),
                Text('Save to Memory?',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'I learned some things about your cooking preferences. '
              'Save them so I can be more helpful next time?',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _confirmMemory,
                    child: const Text('Yes, Save'),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _declineMemory,
                    child: const Text('No Thanks'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryConfirmed(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.cardPadding),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                'Preferences saved! I\'ll remember for next time.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryDeclined(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.cardPadding),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                'No problem! Nothing was saved.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
