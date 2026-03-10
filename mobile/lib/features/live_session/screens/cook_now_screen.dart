import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../core/api_client.dart';
import '../../../core/session_api.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/widgets/error_display.dart';

/// Zero-setup Cook Now screen — voice/video call-like entry.
///
/// Designed as a call-like experience: large Start button opens live voice
/// session immediately. Optional context available via expandable section.
/// No mandatory text fields — all context can be provided by voice.
class CookNowScreen extends StatefulWidget {
  const CookNowScreen({super.key});

  @override
  State<CookNowScreen> createState() => _CookNowScreenState();
}

class _CookNowScreenState extends State<CookNowScreen> {
  bool _loading = false;
  String? _error;
  bool _cameraEnabled = false;
  bool _showOptionalContext = false;

  /// Timestamp when the screen was opened — for zero-setup funnel timing.
  late final DateTime _entryTime;

  // Optional context (all skippable)
  final _goalController = TextEditingController();
  String? _selectedTime;
  static const _timeOptions = ['15 min', '30 min', '45 min', '1 hour'];

  @override
  void initState() {
    super.initState();
    _entryTime = DateTime.now();
    _emitAnalyticsEvent('zero_setup_entry_tapped');
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  /// Emit a product analytics event via the backend.
  Future<void> _emitAnalyticsEvent(String eventType, [Map<String, dynamic>? metadata]) async {
    try {
      final api = context.read<ApiClient>();
      await api.post('/v1/analytics/events', body: {
        'event_type': eventType,
        if (metadata != null) 'metadata': metadata,
      });
    } catch (e) {
      debugPrint('Analytics event $eventType failed: $e');
    }
  }

  Future<void> _startSession() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();

      // Build freestyle context from optional inputs
      final freestyleContext = <String, dynamic>{};
      final goal = _goalController.text.trim();
      if (goal.isNotEmpty) freestyleContext['dish_goal'] = goal;
      if (_selectedTime != null) {
        final minutes = _parseTimeMinutes(_selectedTime!);
        if (minutes != null) freestyleContext['time_budget_minutes'] = minutes;
      }

      final body = <String, dynamic>{
        'session_mode': 'freestyle',
        'interaction_mode':
            _cameraEnabled ? 'voice_video_call' : 'voice_only',
        'allow_text_input': false,
        if (freestyleContext.isNotEmpty) 'freestyle_context': freestyleContext,
      };

      final data = await api.postWithRetry('/v1/sessions', body: body);
      final sessionId = data['session_id'] as String? ?? '';

      // Track zero-setup session creation
      if (sessionId.isNotEmpty) {
        final elapsed = DateTime.now().difference(_entryTime).inMilliseconds;
        _emitAnalyticsEvent('zero_setup_session_created', {
          'session_id': sessionId,
          'entry_to_creation_ms': elapsed,
        });
      }

      if (sessionId.isEmpty) {
        if (mounted) {
          setState(() => _error = 'Failed to create session. Try again.');
        }
        return;
      }

      // Activate
      final sessionApi = SessionApiService(api: api);
      final activateResponse = await sessionApi.activate(sessionId);

      if (mounted && activateResponse.status == 'active') {
        context.go(AppRoutes.sessionPath(sessionId));
      } else if (mounted) {
        setState(
            () => _error = 'Session created but activation failed. Try again.');
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
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Seasoned Chef Buddy'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _loading ? null : () => context.go(AppRoutes.home),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable content area
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: Spacing.xl),

                    // Buddy avatar / mic icon
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primaryContainer,
                      ),
                      child: Icon(
                        _loading ? Icons.hourglass_top : Icons.restaurant,
                        size: 56,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),

                    Text(
                      _loading
                          ? 'Connecting...'
                          : 'Ready to cook together',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'Your buddy will guide you by voice.\n'
                      'No recipe needed — just start talking.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // Error display
                    if (_error != null) ...[
                      const SizedBox(height: Spacing.md),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.pagePadding),
                        child: ErrorDisplay(
                          message: _error!,
                          onRetry: _startSession,
                        ),
                      ),
                    ],

                    const SizedBox(height: Spacing.md),

                    // Toggle optional context
                    TextButton.icon(
                      onPressed: () {
                        setState(
                            () => _showOptionalContext = !_showOptionalContext);
                      },
                      icon: Icon(_showOptionalContext
                          ? Icons.expand_less
                          : Icons.expand_more),
                      label: Text(_showOptionalContext
                          ? 'Hide options'
                          : 'Add optional context'),
                    ),

                    // Optional context (collapsible — not required)
                    if (_showOptionalContext)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.pagePadding),
                        child: Column(
                          children: [
                            TextField(
                              controller: _goalController,
                              decoration: const InputDecoration(
                                hintText: 'What are you making? (optional)',
                                prefixIcon: Icon(Icons.restaurant_menu),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: Spacing.sm),
                            Wrap(
                              spacing: Spacing.sm,
                              children: _timeOptions.map((t) {
                                return ChoiceChip(
                                  label: Text(t),
                                  selected: _selectedTime == t,
                                  onSelected: (v) {
                                    setState(
                                        () => _selectedTime = v ? t : null);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: Spacing.sm),
                          ],
                        ),
                      ),

                    const SizedBox(height: Spacing.md),
                  ],
                ),
              ),
            ),

            const SizedBox(height: Spacing.sm),

            // Call controls bar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.pagePadding, 0, Spacing.pagePadding, Spacing.lg),
              child: Column(
                children: [
                  // Camera toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CallControlButton(
                        icon: _cameraEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        label:
                            _cameraEnabled ? 'Camera On' : 'Camera Off',
                        onTap: () => setState(
                            () => _cameraEnabled = !_cameraEnabled),
                        isActive: _cameraEnabled,
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.md),

                  // Primary CTA — Start call
                  SizedBox(
                    width: double.infinity,
                    height: 72,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _startSession,
                      icon: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.call, size: 28),
                      label: Text(
                        _loading ? 'Connecting...' : 'Start Cooking',
                        style: const TextStyle(fontSize: 20),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.xl),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Call control button (camera toggle, mute, etc.)
class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Material(
          shape: const CircleBorder(),
          color: isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(
                icon,
                size: 28,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
