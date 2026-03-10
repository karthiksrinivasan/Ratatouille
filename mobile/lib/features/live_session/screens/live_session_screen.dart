import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/audio_capture.dart';
import '../../../core/audio_playback.dart';
import '../../../core/camera_service.dart';
import '../../../core/permission_service.dart';
import '../../../core/ws_client.dart';
import '../../../core/auth_service.dart';
import '../widgets/process_bar.dart';
import '../widgets/conflict_chooser.dart';
import '../widgets/guide_image_overlay.dart';
import '../widgets/call_chrome.dart';
import '../widgets/buddy_caption.dart';

/// Speaking/connection state for the live session UI.
enum BuddyState { listening, speaking, interrupted, reconnecting, degraded }

/// Live cooking session screen — FaceTime-style "call with mom" experience.
///
/// Full-screen camera preview with voice captions, call controls,
/// guide image overlays, and process tracking. No text-message UI.
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

  // Services
  final AudioCaptureService _audioCapture = AudioCaptureService();
  final AudioPlaybackService _audioPlayback = AudioPlaybackService();
  final CameraService _camera = CameraService();
  final PermissionService _permissions = PermissionService();

  // Core state
  BuddyState _buddyState = BuddyState.listening;
  bool _isMuted = false;
  bool _ambientEnabled = false;
  int _currentStep = 1;
  String _lastBuddyMessage = '';
  String _connectionLabel = 'Connecting...';
  bool _textInputMode = false;
  bool _wsMaxRetriesReached = false;

  // Permissions
  bool _micGranted = false;
  bool _cameraGranted = false;

  // Guide overlay state
  bool _showGuide = false;
  String _guideImageUrl = '';
  String _guideCaption = '';
  List<String> _guideCues = [];

  // Browse mode state (Epic 6 / Task 4.12)
  bool _browseActive = false;
  List<Map<String, dynamic>> _browseIngredients = [];
  String? _browseQuestion;

  // Epic 5 — process tracking state
  List<CookingProcess> _processes = [];
  List<String> _attentionNeeded = [];
  CookingProcess? _nextDue;

  // P1 conflict state
  List<ConflictOption>? _conflictOptions;
  String? _conflictMessage;
  int _conflictTimeout = 30;

  // Interrupted content
  String? _interruptedPreview;
  bool _hasInterruptedContent = false;

  // Timers
  Timer? _pingTimer;
  Timer? _ambientFrameTimer;
  final TextEditingController _textController = TextEditingController();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _ws = widget.wsClient ?? WsClient(authService: AuthService());
    _ws.addListener(_onConnectionStateChanged);
    _messageSub = _ws.messages.listen(_onMessage);
    _initSession();
  }

  Future<void> _initSession() async {
    // 1. Request permissions
    final result = await _permissions.requestMicCamera();
    _micGranted = result.micGranted;
    _cameraGranted = result.cameraGranted;

    // 2. Initialize camera if granted
    if (_cameraGranted) {
      await _camera.initialize(front: false);
    }

    // 3. Connect WebSocket
    await _ws.connect(widget.sessionId);
    _startPingTimer();

    // 4. Start audio capture if mic granted
    if (_micGranted) {
      await _audioCapture.start(onAudioChunk: _onAudioChunk);
      setState(() => _connectionLabel = 'Listening...');
    } else {
      setState(() {
        _buddyState = BuddyState.degraded;
        _textInputMode = true;
        _connectionLabel = 'Text-only mode (no mic)';
      });
    }

    if (mounted) setState(() {});
  }

  void _onAudioChunk(String base64Audio) {
    if (_ws.isConnected && !_isMuted) {
      _ws.sendAudio(base64Audio);
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_ws.isConnected) _ws.sendPing();
    });
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _ambientFrameTimer?.cancel();
    _textController.dispose();
    _messageSub?.cancel();
    _ws.removeListener(_onConnectionStateChanged);
    _audioCapture.dispose();
    _audioPlayback.dispose();
    _camera.dispose();
    if (widget.wsClient == null) {
      _ws.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // WS Connection State
  // ---------------------------------------------------------------------------

  void _onConnectionStateChanged() {
    if (!mounted) return;
    setState(() {
      if (_ws.maxRetriesReached) {
        _wsMaxRetriesReached = true;
        _buddyState = BuddyState.reconnecting;
        _connectionLabel = 'Connection lost';
      } else if (_ws.state == WsConnectionState.error ||
          _ws.state == WsConnectionState.disconnected) {
        _buddyState = BuddyState.reconnecting;
        _connectionLabel = 'Reconnecting...';
        _wsMaxRetriesReached = false;
      } else if (_ws.state == WsConnectionState.connected) {
        _wsMaxRetriesReached = false;
        if (_buddyState == BuddyState.reconnecting) {
          _buddyState = _micGranted ? BuddyState.listening : BuddyState.degraded;
          _connectionLabel = _micGranted ? 'Listening...' : 'Text-only mode';
          _ws.sendSessionResume();
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // WS Message Handler
  // ---------------------------------------------------------------------------

  void _onMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type'] as String?;

    setState(() {
      switch (type) {
        // --- Audio ---
        case 'buddy_audio':
          final audio = msg['audio'] as String?;
          if (audio != null) {
            _audioPlayback.play(audio);
            _buddyState = BuddyState.speaking;
            _connectionLabel = 'Buddy speaking...';
          }
          break;
        case 'buddy_interrupted':
          _audioPlayback.stopImmediately(); // <200ms barge-in
          _buddyState = BuddyState.interrupted;
          _connectionLabel = 'Interrupted';
          _interruptedPreview = msg['interrupted_text'] as String?;
          _hasInterruptedContent = msg['resumable'] as bool? ?? false;
          break;

        // --- Text / Caption ---
        case 'buddy_message':
        case 'buddy_response':
          _buddyState = BuddyState.speaking;
          _lastBuddyMessage = msg['text'] as String? ?? '';
          _currentStep = msg['step'] as int? ?? _currentStep;
          _connectionLabel = 'Buddy speaking...';
          break;

        // --- Visual Guide ---
        case 'visual_guide':
          _showGuide = true;
          _guideImageUrl = msg['image_url'] as String? ?? '';
          _guideCaption = msg['caption'] as String? ?? '';
          _guideCues = (msg['visual_cues'] as List<dynamic>?)
                  ?.cast<String>() ??
              [];
          break;

        // --- Browse Mode (Task 4.12) ---
        case 'browse_observation':
          _browseActive = true;
          _browseIngredients = (msg['ingredients'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          break;
        case 'ingredient_candidates':
          _browseIngredients = (msg['candidates'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          break;
        case 'browse_question':
          _browseQuestion = msg['question'] as String?;
          break;
        case 'browse_complete':
          _browseActive = false;
          _browseIngredients = [];
          _browseQuestion = null;
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

        // --- Session state ---
        case 'session_state':
          _currentStep = msg['current_step'] as int? ?? _currentStep;
          _ambientEnabled = msg['ambient_listen'] as bool? ?? _ambientEnabled;
          final text = msg['last_message'] as String?;
          if (text != null && text.isNotEmpty) _lastBuddyMessage = text;
          break;

        // --- Mode ---
        case 'mode_update':
          _ambientEnabled = msg['ambient_listen'] as bool? ?? _ambientEnabled;
          break;

        // --- Keepalive ---
        case 'pong':
          break;

        // --- Error ---
        case 'error':
          _lastBuddyMessage =
              msg['message'] as String? ?? 'Something went wrong.';
          break;
        default:
          break;
      }
    });

    // Auto-transition from speaking back to listening
    if (type == 'buddy_message' ||
        type == 'buddy_response' ||
        type == 'buddy_audio') {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _buddyState == BuddyState.speaking) {
          setState(() {
            _buddyState = BuddyState.listening;
            _connectionLabel = 'Listening...';
          });
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Process Bar Handlers (Epic 5)
  // ---------------------------------------------------------------------------

  void _updateProcessBar(Map<String, dynamic> msg) {
    final processList = msg['processes'] as List<dynamic>? ?? [];
    _processes = processList
        .map((p) => CookingProcess.fromJson(p as Map<String, dynamic>))
        .toList();
    _attentionNeeded =
        (msg['attention_needed'] as List<dynamic>?)?.cast<String>() ?? [];
    final nextDueData = msg['next_due'] as Map<String, dynamic>?;
    _nextDue =
        nextDueData != null ? CookingProcess.fromJson(nextDueData) : null;
  }

  void _handleTimerAlert(Map<String, dynamic> msg) {
    final processName = msg['process_name'] as String? ?? 'Timer';
    _lastBuddyMessage = msg['message'] as String? ?? '$processName is done!';
  }

  void _handleTimerWarning(Map<String, dynamic> msg) {
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

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    if (_isMuted) {
      _audioCapture.stop();
    } else if (_micGranted) {
      _audioCapture.start(onAudioChunk: _onAudioChunk);
    }
  }

  void _flipCamera() {
    _camera.flipCamera().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _endCall() {
    _ambientFrameTimer?.cancel();
    _audioCapture.stop();
    _audioPlayback.stopImmediately();
    context.go(AppRoutes.postSessionPath(widget.sessionId));
  }

  void _dismissGuide() {
    setState(() {
      _showGuide = false;
      _guideImageUrl = '';
      _guideCaption = '';
      _guideCues = [];
    });
  }

  void _onConflictChoice(String processId) {
    _ws.send({'type': 'conflict_choice', 'chosen_process_id': processId});
    setState(() {
      _conflictOptions = null;
      _conflictMessage = null;
    });
  }

  void _onProcessTap(String processId) {
    _ws.send({'type': 'process_complete', 'process_id': processId});
  }

  void _onDelegateTap(String processId) {
    _ws.send({'type': 'process_delegate', 'process_id': processId});
  }

  /// Task 4.13: Toggle ambient mode with rate-limited frame capture.
  void _toggleAmbient() {
    final next = !_ambientEnabled;
    _ws.sendAmbientToggle(next);
    setState(() => _ambientEnabled = next);
    if (next) {
      _ambientFrameTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) async {
          if (_camera.isInitialized && _ws.isConnected) {
            final framePath = await _camera.captureFrameToFile();
            if (framePath != null) {
              _ws.sendVisionCheck(framePath);
            }
          }
        },
      );
    } else {
      _ambientFrameTimer?.cancel();
      _ambientFrameTimer = null;
    }
  }

  /// Task 4.14: Manual reconnect after max retries exhausted.
  void _handleReconnect() {
    setState(() {
      _wsMaxRetriesReached = false;
      _connectionLabel = 'Reconnecting...';
    });
    _ws.resetReconnect();
    _ws.connect(widget.sessionId);
  }

  void _sendTextQuery(String text) {
    _ws.sendVoiceQuery(text);
    _textController.clear();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar — full-screen call experience
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 1: Full-screen camera preview
          _buildCameraPreview(),

          // Layer 2: Process bar at top + step indicator
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Step indicator + ambient toggle
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: Colors.black38,
                    child: Row(
                      children: [
                        Text(
                          'Step $_currentStep',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        // Ambient toggle
                        GestureDetector(
                          onTap: _toggleAmbient,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _ambientEnabled
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : Colors.white12,
                            ),
                            child: Icon(
                              _ambientEnabled
                                  ? Icons.hearing
                                  : Icons.hearing_disabled,
                              color: _ambientEnabled
                                  ? Colors.green
                                  : Colors.white70,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Ambient privacy banner
                  if (_ambientEnabled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 16,
                      ),
                      color: Colors.green.withValues(alpha: 0.2),
                      child: const Text(
                        'Ambient ON — audio not stored',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  // Sticky process bar
                  ProcessBar(
                    processes: _processes,
                    attentionNeeded: _attentionNeeded,
                    nextDue: _nextDue,
                    onProcessTap: _onProcessTap,
                    onDelegateTap: _onDelegateTap,
                  ),
                ],
              ),
            ),
          ),

          // Layer 3: Buddy caption + connection state above call chrome
          Positioned(
            left: 0,
            right: 0,
            bottom: 120, // Above call chrome
            child: BuddyCaption(
              text: _lastBuddyMessage,
              connectionState: _connectionLabel,
            ),
          ),

          // Interrupted content chip
          if (_hasInterruptedContent && _interruptedPreview != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 200,
              child: Center(
                child: ActionChip(
                  avatar: const Icon(Icons.replay, size: 18),
                  label: const Text('Interrupted — tap to resume'),
                  backgroundColor: Colors.black54,
                  labelStyle: const TextStyle(color: Colors.white),
                  onPressed: () {
                    _ws.sendResumeInterrupted();
                    setState(() {
                      _hasInterruptedContent = false;
                      _interruptedPreview = null;
                    });
                  },
                ),
              ),
            ),

          // Layer 4: Call chrome at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: CallChrome(
                isMuted: _isMuted,
                onToggleMute: _toggleMute,
                onFlipCamera: _flipCamera,
                onEndCall: _endCall,
              ),
            ),
          ),

          // P1 conflict chooser (overlays when active)
          if (_conflictOptions != null && _conflictOptions!.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.of(context).size.height * 0.3,
              child: ConflictChooser(
                options: _conflictOptions!,
                message: _conflictMessage ?? 'Choose which to handle first',
                timeoutSeconds: _conflictTimeout,
                onChoice: _onConflictChoice,
                onTimeout: () {
                  setState(() {
                    _conflictOptions = null;
                    _conflictMessage = null;
                  });
                },
              ),
            ),

          // Task 4.12: Browse mode floating ingredient labels
          if (_browseActive) _buildBrowseOverlay(),

          // Layer 5: Guide image overlay (conditional)
          if (_showGuide)
            GuideImageOverlay(
              imageUrl: _guideImageUrl,
              caption: _guideCaption,
              visualCues: _guideCues,
              onDismiss: _dismissGuide,
              cameraPip: _buildCameraPip(),
            ),

          // Task 4.14: Reconnect button after max retries
          if (_wsMaxRetriesReached)
            Positioned(
              top: MediaQuery.of(context).size.height / 2 - 30,
              left: 40,
              right: 40,
              child: FilledButton.icon(
                onPressed: _handleReconnect,
                icon: const Icon(Icons.wifi),
                label: const Text('Connection Lost — Tap to Reconnect'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),

          // Degraded/text input mode (no mic permission fallback)
          if (_textInputMode)
            Positioned(
              left: 16,
              right: 16,
              bottom: 130,
              child: _TextInputBar(
                controller: _textController,
                onSend: _sendTextQuery,
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-widgets
  // ---------------------------------------------------------------------------

  Widget _buildCameraPreview() {
    if (!_camera.isInitialized || _camera.controller == null) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _camera.controller!.value.previewSize?.height ?? 1,
          height: _camera.controller!.value.previewSize?.width ?? 1,
          child: CameraPreview(_camera.controller!),
        ),
      ),
    );
  }

  Widget _buildCameraPip() {
    if (!_camera.isInitialized || _camera.controller == null) {
      return Container(color: Colors.black);
    }
    return CameraPreview(_camera.controller!);
  }

  /// Task 4.12: Browse mode overlay — floating ingredient labels over camera.
  Widget _buildBrowseOverlay() {
    return Positioned(
      left: 16,
      right: 16,
      top: MediaQuery.of(context).size.height * 0.15,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Scanning ingredients...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_browseQuestion != null) ...[
              const SizedBox(height: 8),
              Text(
                _browseQuestion!,
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _browseIngredients.map((ingredient) {
                final name = ingredient['name'] as String? ?? '';
                final confidence =
                    ingredient['confidence'] as double? ?? 0.0;
                return Chip(
                  label: Text(name),
                  backgroundColor: confidence > 0.8
                      ? Colors.green.withValues(alpha: 0.3)
                      : confidence > 0.5
                          ? Colors.orange.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                  labelStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Type your question...',
                hintStyle: TextStyle(color: Colors.white54),
                isDense: true,
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) onSend(text.trim());
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.white70),
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
