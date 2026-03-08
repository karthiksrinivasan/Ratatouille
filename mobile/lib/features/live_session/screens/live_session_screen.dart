import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/ws_client.dart';
import '../../../core/auth_service.dart';

/// Speaking/connection state for the live session UI.
enum BuddyState { listening, speaking, interrupted, reconnecting }

/// Live cooking session screen with real-time AI guidance.
///
/// Connects to the backend via WebSocket for step-by-step cooking
/// instructions, voice interaction, and hands-busy ergonomics.
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

  @override
  void initState() {
    super.initState();
    _ws = widget.wsClient ?? WsClient(authService: AuthService());
    _ws.addListener(_onConnectionStateChanged);
    _messageSub = _ws.messages.listen(_onMessage);
    _ws.connect(widget.sessionId);
  }

  @override
  void dispose() {
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

            // Hands-busy controls — large tap targets
            _HandsBusyControls(
              onNextStep: () => _ws.sendStepComplete(_currentStep),
              onVisionCheck: () => context.go(AppRoutes.visionGuidePath(widget.sessionId)),
              onRepeatQuickly: () => _ws.sendVoiceQuery('repeat quickly'),
              onFinish: () => context.go(AppRoutes.postSessionPath(widget.sessionId)),
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

/// Large, ergonomic controls for hands-busy cooking context.
class _HandsBusyControls extends StatelessWidget {
  final VoidCallback onNextStep;
  final VoidCallback onVisionCheck;
  final VoidCallback onRepeatQuickly;
  final VoidCallback onFinish;

  const _HandsBusyControls({
    required this.onNextStep,
    required this.onVisionCheck,
    required this.onRepeatQuickly,
    required this.onFinish,
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
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton.icon(
              onPressed: onFinish,
              icon: const Icon(Icons.check_circle),
              label: const Text('Finish Session'),
            ),
          ),
        ],
      ),
    );
  }
}
