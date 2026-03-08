import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../core/api_client.dart';
import '../../../core/session_api.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/widgets/error_display.dart';

/// Zero-setup Cook Now screen — freestyle session entry.
///
/// Users can optionally provide quick context (goal, time, ingredients)
/// or skip straight to a live session. No mandatory fields.
class CookNowScreen extends StatefulWidget {
  const CookNowScreen({super.key});

  @override
  State<CookNowScreen> createState() => _CookNowScreenState();
}

class _CookNowScreenState extends State<CookNowScreen> {
  final _goalController = TextEditingController();
  final _ingredientsController = TextEditingController();
  String? _selectedTime;
  bool _loading = false;
  String? _error;

  static const _timeOptions = ['15 min', '30 min', '45 min', '1 hour', '1+ hours'];

  @override
  void dispose() {
    _goalController.dispose();
    _ingredientsController.dispose();
    super.dispose();
  }

  Future<void> _startFreestyle({bool skip = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();

      // Build request body matching backend SessionCreate contract
      final freestyleContext = <String, dynamic>{};
      if (!skip) {
        final goal = _goalController.text.trim();
        final ingredients = _ingredientsController.text.trim();
        if (goal.isNotEmpty) freestyleContext['dish_goal'] = goal;
        if (ingredients.isNotEmpty) {
          freestyleContext['available_ingredients'] =
              ingredients.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
        if (_selectedTime != null) {
          final minutes = _parseTimeMinutes(_selectedTime!);
          if (minutes != null) freestyleContext['time_budget_minutes'] = minutes;
        }
      }
      final body = <String, dynamic>{
        'session_mode': 'freestyle',
        if (freestyleContext.isNotEmpty) 'freestyle_context': freestyleContext,
      };

      final data = await api.postWithRetry('/v1/sessions', body: body);
      final sessionId = data['session_id'] as String? ?? '';

      if (sessionId.isEmpty) {
        if (mounted) {
          setState(() => _error = 'Failed to create session. Try again.');
        }
        return;
      }

      // Activate the session
      final sessionApi = SessionApiService(api: api);
      final activateResponse = await sessionApi.activate(sessionId);

      if (mounted && activateResponse.status == 'active') {
        context.go(AppRoutes.sessionPath(sessionId));
      } else if (mounted) {
        setState(() => _error = 'Session created but activation failed. Try again.');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = 'Error: ${e.message}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  static int? _parseTimeMinutes(String label) {
    return switch (label) {
      '15 min' => 15,
      '30 min' => 30,
      '45 min' => 45,
      '1 hour' => 60,
      '1+ hours' => 90,
      _ => null,
    };
  }

  void _goToScanFlow() {
    context.go(AppRoutes.scan);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cook Now'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _loading ? null : () => context.go(AppRoutes.home),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero message
            Icon(
              Icons.mic_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'No recipe needed',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Start cooking with live AI guidance. '
              'Optionally share what you have — or just jump in.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: Spacing.xl),

            // Quick context fields (all optional)
            _buildOptionalField(
              theme,
              label: 'What are you making? (optional)',
              hint: 'e.g. "Something with chicken" or "A quick pasta"',
              controller: _goalController,
            ),
            const SizedBox(height: Spacing.md),

            _buildOptionalField(
              theme,
              label: 'Ingredients on hand (optional)',
              hint: 'e.g. "chicken, garlic, olive oil, pasta"',
              controller: _ingredientsController,
            ),
            const SizedBox(height: Spacing.md),

            // Time estimate chips
            Text(
              'How much time? (optional)',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Wrap(
              spacing: Spacing.sm,
              children: _timeOptions.map((t) {
                final selected = _selectedTime == t;
                return ChoiceChip(
                  label: Text(t),
                  selected: selected,
                  onSelected: (v) {
                    setState(() => _selectedTime = v ? t : null);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: Spacing.xl),

            // Error display
            if (_error != null) ...[
              ErrorDisplay(
                message: _error!,
                onRetry: () => _startFreestyle(),
              ),
              const SizedBox(height: Spacing.md),

              // Fallback options on error
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : _goToScanFlow,
                      child: const Text('Try Scan Instead'),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => context.go(AppRoutes.home),
                      child: const Text('Back to Home'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
            ],

            // Primary CTA — Skip & Start (1 tap to live session)
            SizedBox(
              height: TouchTargets.handsBusy,
              child: FilledButton.icon(
                onPressed: _loading ? null : () => _startFreestyle(skip: true),
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_loading ? 'Starting...' : 'Skip & Start Cooking'),
              ),
            ),

            const SizedBox(height: Spacing.sm),

            // Secondary CTA — Start with context
            SizedBox(
              height: TouchTargets.handsBusy,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : () => _startFreestyle(),
                icon: const Icon(Icons.tune),
                label: const Text('Start with Context'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionalField(
    ThemeData theme, {
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Spacing.xs),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
