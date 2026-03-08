import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/ws_client.dart';
import '../../../core/auth_service.dart';
import '../widgets/process_bar.dart';
import '../widgets/conflict_chooser.dart';

/// Speaking/connection state for the live session UI.
enum BuddyState { listening, speaking, interrupted, reconnecting, degraded }

/// Live cooking session screen with real-time AI guidance.
///
/// Connects to the backend via WebSocket for step-by-step cooking
/// instructions, voice interaction, and hands-busy ergonomics.
/// Includes sticky process bar (Epic 5) and P1 conflict chooser.
class LiveSessionScreen extends StatefulWidget {
  final String sessionId;
  final WsClient? wsClient; // injectable for testing

  const LiveSessionScreen({
    super.key,
    required this.sessionId,
    this.wsClient,
  });

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  late final WsClient _ws;
  StreamSubscription<Map<String, dynamic>>? _messageSub;

  BuddyState _buddyState = BuddyState.listening;
  bool _ambientEnabled = false;
  int _currentStep = 1;
  String _lastBuddyMessage = '';
  String? _interruptedPreview;
  bool _hasInterruptedContent = false;
  bool _textInputMode = false; // Degraded mode: text input fallback

  // Epic 5 — process tracking state
  List<CookingProcess> _processes = [];
  List<String> _attentionNeeded = [];
  CookingProcess? _nextDue;

  // P1 conflict state
  List<ConflictOption>? _conflictOptions;
  String? _conflictMessage;
  int _conflictTimeout = 30;

  // Keep-alive ping timer
  Timer? _pingTimer;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ws = widget.wsClient ?? WsClient(authService: AuthService());
    _ws.addListener(_onConnectionStateChanged);
    _messageSub = _ws.messages.listen(_onMessage);
    _ws.connect(widget.sessionId);
    _startPingTimer();
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_ws.isConnected) {
        _ws.sendPing();
      }
    });
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _textController.dispose();
    _messageSub?.cancel();
    _ws.removeListener(_onConnectionStateChanged);
    if (widget.wsClient == null) {
      _ws.dispose();
    }
    super.dispose();
  }

  void _onConnectionStateChanged() {
    if (!mounted) return;
    setState(() {
      if (_ws.state == WsConnectionState.error ||
          _ws.state == WsConnectionState.disconnected) {
        _buddyState = BuddyState.reconnecting;
      } else if (_ws.state == WsConnectionState.connected) {
        if (_buddyState == BuddyState.reconnecting) {
          _buddyState = BuddyState.listening;
          // Request latest session state after reconnect
          _ws.sendSessionResume();
        }
      }
    });
  }

  void _onMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type'] as String?;

    setState(() {
      switch (type) {
        case 'buddy_message':
        case 'buddy_response':
          _buddyState = BuddyState.speaking;
          _lastBuddyMessage = msg['text'] as String? ?? '';
          _currentStep = msg['step'] as int? ?? _currentStep;
          break;
        case 'buddy_interrupted':
          _buddyState = BuddyState.interrupted;
          _interruptedPreview = msg['interrupted_text'] as String?;
          _hasInterruptedContent = msg['resumable'] as bool? ?? false;
          break;
        case 'mode_update':
          _ambientEnabled = msg['ambient_listen'] as bool? ?? _ambientEnabled;
          break;

        // --- Epic 5: Process events ---
        case 'process_update':
          _updateProcessBar(msg);
          break;
        case 'timer_alert':
          _handleTimerAlert(msg);
          break;
        case 'timer_warning':
          _handleTimerWarning(msg);
          break;
        case 'priority_conflict':
          _handlePriorityConflict(msg);
          break;
        case 'conflict_resolved':
          _conflictOptions = null;
          _conflictMessage = null;
          break;

        // Session state restored after reconnect
        case 'session_state':
          _currentStep = msg['current_step'] as int? ?? _currentStep;
          _ambientEnabled = msg['ambient_listen'] as bool? ?? _ambientEnabled;
          final text = msg['last_message'] as String?;
          if (text != null && text.isNotEmpty) {
            _lastBuddyMessage = text;
          }
          break;

        case 'pong':
          break;
        case 'error':
          _lastBuddyMessage = msg['message'] as String? ?? 'Something went wrong.';
          break;
        default:
          break;
      }
    });

    // Auto-transition from speaking back to listening after a brief delay
    if (type == 'buddy_message' || type == 'buddy_response') {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _buddyState == BuddyState.speaking) {
          setState(() => _buddyState = BuddyState.listening);
        }
      });
    }
  }

  void _updateProcessBar(Map<String, dynamic> msg) {
    final processList = msg['processes'] as List<dynamic>? ?? [];
    _processes = processList
        .map((p) => CookingProcess.fromJson(p as Map<String, dynamic>))
        .toList();
    _attentionNeeded = (msg['attention_needed'] as List<dynamic>?)
            ?.cast<String>() ??
        [];
    final nextDueData = msg['next_due'] as Map<String, dynamic>?;
    _nextDue = nextDueData != null ? CookingProcess.fromJson(nextDueData) : null;
  }

  void _handleTimerAlert(Map<String, dynamic> msg) {
    final processName = msg['process_name'] as String? ?? 'Timer';
    _lastBuddyMessage = msg['message'] as String? ?? '$processName is done!';
  }

  void _handleTimerWarning(Map<String, dynamic> msg) {
    // Show as a snackbar — non-blocking
    final processName = msg['process_name'] as String? ?? 'Timer';
    final remaining = msg['remaining_seconds'] as int? ?? 60;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$processName — ${remaining}s left'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    });
  }

  void _handlePriorityConflict(Map<String, dynamic> msg) {
    final options = (msg['options'] as List<dynamic>?)
        ?.map((o) => ConflictOption.fromJson(o as Map<String, dynamic>))
        .toList();
    _conflictOptions = options;
    _conflictMessage =
        msg['message'] as String? ?? 'Two things need your attention!';
    _conflictTimeout = msg['timeout_seconds'] as int? ?? 30;
  }

  void _onConflictChoice(String processId) {
    _ws.send({'type': 'conflict_choice', 'chosen_process_id': processId});
    setState(() {
      _conflictOptions = null;
      _conflictMessage = null;
    });
  }

  void _onProcessTap(String processId) {
    // Mark process as complete
    _ws.send({'type': 'process_complete', 'process_id': processId});
  }

  void _onDelegateTap(String processId) {
    // Delegate process to buddy
    _ws.send({'type': 'process_delegate', 'process_id': processId});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cooking Session'),
        actions: [
          // Ambient privacy indicator
          _AmbientIndicator(
            enabled: _ambientEnabled,
            onToggle: () {
              final next = !_ambientEnabled;
              _ws.sendAmbientToggle(next);
              setState(() => _ambientEnabled = next);
            },
          ),
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: 'Visual Guide',
            onPressed: () => context.go(AppRoutes.visionGuidePath(widget.sessionId)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Connection / speaking state banner
            _StateBanner(state: _buddyState),

            // Ambient privacy banner — always visible when enabled
            if (_ambientEnabled)
              const _AmbientPrivacyBanner(),

            // Sticky process bar (Epic 5)
            ProcessBar(
              processes: _processes,
              attentionNeeded: _attentionNeeded,
              nextDue: _nextDue,
              onProcessTap: _onProcessTap,
              onDelegateTap: _onDelegateTap,
            ),

            // P1 conflict chooser (overlays content when active)
            if (_conflictOptions != null && _conflictOptions!.isNotEmpty)
              ConflictChooser(
                options: _conflictOptions!,
                message: _conflictMessage ?? 'Choose which to handle first',
                timeoutSeconds: _conflictTimeout,
                onChoice: _onConflictChoice,
                onTimeout: () {
                  // Let backend handle timeout triage
                  setState(() {
                    _conflictOptions = null;
                    _conflictMessage = null;
                  });
                },
              ),

            // Buddy message area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    // Step indicator
                    Text(
                      'Step $_currentStep',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    // Buddy message
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          _lastBuddyMessage,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 20, // Readable at arm's length
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    // Interrupted chip
                    if (_hasInterruptedContent && _interruptedPreview != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.replay, size: 18),
                          label: const Text('Interrupted — tap to resume summary'),
                          onPressed: () {
                            _ws.sendResumeInterrupted();
                            setState(() {
                              _hasInterruptedContent = false;
                              _interruptedPreview = null;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Degraded/reconnecting mode text input (voice unavailable fallback)
            if (_textInputMode || _buddyState == BuddyState.degraded || _buddyState == BuddyState.reconnecting)
              _TextInputBar(
                controller: _textController,
                onSend: (text) {
                  _ws.sendVoiceQuery(text);
                  _textController.clear();
                },
              ),

            // Hands-busy controls — large tap targets
            _HandsBusyControls(
              onNextStep: () => _ws.sendStepComplete(_currentStep),
              onVisionCheck: () => context.go(AppRoutes.visionGuidePath(widget.sessionId)),
              onRepeatQuickly: () => _ws.sendVoiceQuery('repeat quickly'),
              onFinish: () => context.go(AppRoutes.postSessionPath(widget.sessionId)),
              // Text mode toggle only shown when voice is unavailable
              onToggleTextMode: (_buddyState == BuddyState.degraded || _buddyState == BuddyState.reconnecting)
                  ? () => setState(() => _textInputMode = !_textInputMode)
                  : null,
              textModeActive: _textInputMode,
            ),
          ],
        ),
      ),
    );
  }
}

/// Persistent ambient-listen indicator with explicit ON/OFF state.
class _AmbientIndicator extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggle;

  const _AmbientIndicator({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: enabled
          ? 'Ambient listening ON — only cooking-related speech triggers responses'
          : 'Ambient listening OFF — tap mic to ask questions',
      child: IconButton(
        icon: Icon(
          enabled ? Icons.hearing : Icons.hearing_disabled,
          color: enabled ? Colors.green : null,
        ),
        onPressed: onToggle,
      ),
    );
  }
}

/// Top banner showing current speaking/connection state.
class _StateBanner extends StatelessWidget {
  final BuddyState state;

  const _StateBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (state) {
      BuddyState.listening => (Icons.mic, 'Listening', Colors.blue),
      BuddyState.speaking => (Icons.volume_up, 'Buddy speaking', Colors.green),
      BuddyState.interrupted => (Icons.pause_circle, 'Interrupted', Colors.orange),
      BuddyState.reconnecting => (Icons.wifi_off, 'Reconnecting...', Colors.red),
      BuddyState.degraded => (Icons.text_fields, 'Text-only mode', Colors.amber),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: color.withValues(alpha: 0.12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Prominent privacy banner shown when ambient listening is active.
class _AmbientPrivacyBanner extends StatelessWidget {
  const _AmbientPrivacyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      color: Colors.green.withValues(alpha: 0.12),
      child: const Row(
        children: [
          Icon(Icons.hearing, size: 16, color: Colors.green),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ambient listening ON — audio is not stored',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large, ergonomic controls for hands-busy cooking context.
/// Text input bar for degraded (text-only) mode.
class _TextInputBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSend;

  const _TextInputBar({
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Type your question...',
                isDense: true,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) onSend(text.trim());
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) onSend(text);
            },
          ),
        ],
      ),
    );
  }
}

class _HandsBusyControls extends StatelessWidget {
  final VoidCallback onNextStep;
  final VoidCallback onVisionCheck;
  final VoidCallback onRepeatQuickly;
  final VoidCallback onFinish;
  final VoidCallback? onToggleTextMode;
  final bool textModeActive;

  const _HandsBusyControls({
    required this.onNextStep,
    required this.onVisionCheck,
    required this.onRepeatQuickly,
    required this.onFinish,
    this.onToggleTextMode,
    this.textModeActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          // Primary action — extra large
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton.icon(
              onPressed: onNextStep,
              icon: const Icon(Icons.skip_next, size: 28),
              label: const Text('Next Step', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 12),
          // Secondary actions
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: onVisionCheck,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Vision Check'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: onRepeatQuickly,
                    icon: const Icon(Icons.replay),
                    label: const Text('Repeat'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (onToggleTextMode != null)
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: TextButton.icon(
                      onPressed: onToggleTextMode,
                      icon: Icon(textModeActive ? Icons.mic : Icons.keyboard),
                      label: Text(textModeActive ? 'Voice Mode' : 'Type Instead'),
                    ),
                  ),
                ),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextButton.icon(
                    onPressed: onFinish,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Finish Session'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
