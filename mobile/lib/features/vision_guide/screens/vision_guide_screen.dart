import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../core/api_client.dart';
import '../../../core/camera_service.dart';
import '../../../core/session_api.dart';

/// Full vision/guide/taste/recovery UX for live cooking sessions (Epic 6).
///
/// Tabs:
///   1. Vision Check — capture frame, display confidence-tiered result
///   2. Guide Image — side-by-side comparison with cue overlays
///   3. Taste Check — conversational diagnostic taste flow
///   4. Recovery — emergency-style recovery with instant-feel UX
class VisionGuideScreen extends StatefulWidget {
  final String sessionId;
  final ApiClient? apiClient; // injectable for testing

  const VisionGuideScreen({super.key, required this.sessionId, this.apiClient});

  @override
  State<VisionGuideScreen> createState() => _VisionGuideScreenState();
}

class _VisionGuideScreenState extends State<VisionGuideScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cooking Tools'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.sessionPath(widget.sessionId)),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.camera_alt), text: 'Vision'),
            Tab(icon: Icon(Icons.compare), text: 'Guide'),
            Tab(icon: Icon(Icons.restaurant), text: 'Taste'),
            Tab(icon: Icon(Icons.warning_amber), text: 'Recovery'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          VisionCheckTab(sessionId: widget.sessionId, apiClient: widget.apiClient),
          GuideImageTab(sessionId: widget.sessionId, apiClient: widget.apiClient),
          TasteCheckTab(sessionId: widget.sessionId, apiClient: widget.apiClient),
          RecoveryTab(sessionId: widget.sessionId, apiClient: widget.apiClient),
        ],
      ),
    );
  }
}

// =============================================================================
// Vision Check Tab (Task 6.1)
// — Wired to real API via SessionApiService.visionCheck()
// — Confidence-tier UX: >=0.8 green, >=0.5 amber, >=0.2 orange, <0.2 red
// =============================================================================

class VisionCheckTab extends StatefulWidget {
  final String sessionId;
  final ApiClient? apiClient;

  const VisionCheckTab({super.key, required this.sessionId, this.apiClient});

  @override
  State<VisionCheckTab> createState() => VisionCheckTabState();
}

class VisionCheckTabState extends State<VisionCheckTab> {
  final CameraService _camera = CameraService();
  bool _loading = false;
  bool _cameraReady = false;
  VisionCheckResponse? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await _camera.initialize(front: false);
      if (mounted) setState(() => _cameraReady = true);
    } catch (_) {
      // Camera not available — user can still see the flow
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  Future<void> _captureAndCheck() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      // Capture frame from camera
      final framePath = await _camera.captureFrameToFile();
      if (framePath == null) {
        setState(() {
          _loading = false;
          _error = 'Could not capture frame. Check camera permissions.';
        });
        return;
      }

      // Upload frame and get vision check via real API
      if (!mounted) return;
      final api = widget.apiClient ?? context.read<ApiClient>();
      final uploadResult = await api.uploadFile(
        '/v1/upload',
        filePath: framePath,
      );
      final frameUri = uploadResult['uri'] as String? ?? '';

      final sessionApi = SessionApiService(api: api);
      final response = await sessionApi.visionCheck(
        widget.sessionId,
        frameUri: frameUri,
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _result = response;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Vision check failed: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Camera preview placeholder
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _cameraReady && _camera.controller != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _camera.controller!.value.previewSize?.height ?? 1,
                        height: _camera.controller!.value.previewSize?.width ?? 1,
                        child: CameraPreview(_camera.controller!),
                      ),
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 48, color: Colors.white54),
                        SizedBox(height: 8),
                        Text(
                          'Camera Preview',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 16),

          // Capture button — large tap target
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _captureAndCheck,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.camera, size: 24),
              label: Text(
                _loading ? 'Analyzing...' : 'Check Doneness',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Vision result card with confidence tiers
          if (_result != null) _VisionConfidenceCard(result: _result!),
          if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Confidence-tiered vision result card.
///
/// Tiers:
///   >= 0.8 → green "Looks great!"
///   >= 0.5 → amber "Getting there" + sensory prompt
///   >= 0.2 → orange "Hard to tell — try repositioning"
///   <  0.2 → red "Using sensory guidance instead"
class _VisionConfidenceCard extends StatelessWidget {
  final VisionCheckResponse result;

  const _VisionConfidenceCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidence = result.confidence;

    final (Color tierColor, String tierLabel, String tierMessage, bool showSensory) =
        confidence >= 0.8
            ? (Colors.green, 'Looks great!', '', false)
            : confidence >= 0.5
                ? (Colors.amber.shade700, 'Getting there', 'Try a sensory check to confirm.', true)
                : confidence >= 0.2
                    ? (Colors.orange, 'Hard to tell', 'Try repositioning for a clearer view.', false)
                    : (Colors.red, 'Using sensory guidance instead', '', true);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Confidence tier badge + numeric value
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: tierColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tierLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(confidence * 100).toInt()}% confidence',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Assessment text
            if (result.assessment.isNotEmpty)
              Text(
                result.assessment,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
              ),

            // Tier-specific message
            if (tierMessage.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                tierMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tierColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // Observations
            if (result.observations.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...result.observations.map((obs) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.visibility, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(obs, style: const TextStyle(fontSize: 14)),
                        ),
                      ],
                    ),
                  )),
            ],

            // Recommendation
            if (result.recommendation.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.recommendation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Sensory prompt for medium/low confidence
            if (showSensory) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.hearing, size: 18, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sensory check: Poke with a fork or taste a small piece for a more reliable assessment.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Guide Image Tab (Task 6.2)
// — Wired to real API via SessionApiService.visualGuide()
// — Visual cues displayed as positioned labels on guide image
// =============================================================================

class GuideImageTab extends StatefulWidget {
  final String sessionId;
  final ApiClient? apiClient;

  const GuideImageTab({super.key, required this.sessionId, this.apiClient});

  @override
  State<GuideImageTab> createState() => GuideImageTabState();
}

class GuideImageTabState extends State<GuideImageTab> {
  bool _loading = false;
  VisualGuideResponse? _guideResult;
  String? _error;
  String _stageLabel = 'target';

  Future<void> _requestGuide() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = widget.apiClient ?? context.read<ApiClient>();
      final sessionApi = SessionApiService(api: api);
      final response = await sessionApi.visualGuide(
        widget.sessionId,
        stage: _stageLabel,
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _guideResult = response;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Guide request failed: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Side-by-side comparison area
          Row(
            children: [
              // User's frame
              Expanded(
                child: Column(
                  children: [
                    Text('Your Frame', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.camera_alt, color: Colors.white38, size: 32),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Target state — shows guide image with cue overlays
              Expanded(
                child: Column(
                  children: [
                    Text('Target State', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _guideResult != null && _guideResult!.guideImageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    _guideResult!.guideImageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.broken_image, color: Colors.grey, size: 32),
                                    ),
                                  ),
                                  // Cue overlay labels positioned on the image
                                  if (_guideResult!.visualCues.isNotEmpty)
                                    Positioned(
                                      left: 4,
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: _guideResult!.visualCues
                                              .take(3)
                                              .map((cue) => Text(
                                                    cue,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : _guideResult != null
                              ? const Center(
                                  child: Icon(Icons.image, color: Colors.grey, size: 32),
                                )
                              : Center(
                                  child: Text(
                                    'Tap Generate',
                                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Visual cues list (full detail below images)
          if (_guideResult != null && _guideResult!.visualCues.isNotEmpty) ...[
            const Text(
              'Visual Cues',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ..._guideResult!.visualCues.map(
              (cue) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(cue, style: const TextStyle(fontSize: 16))),
                  ],
                ),
              ),
            ),
            // Target state label
            if (_guideResult!.targetState.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Target: ${_guideResult!.targetState}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],

          // Error
          if (_error != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Stage selector
          DropdownButtonFormField<String>(
            initialValue: _stageLabel,
            decoration: const InputDecoration(
              labelText: 'Target Stage',
              prefixIcon: Icon(Icons.layers),
            ),
            items: const [
              DropdownMenuItem(value: 'target', child: Text('Target (default)')),
              DropdownMenuItem(value: 'light_golden', child: Text('Light Golden')),
              DropdownMenuItem(value: 'al_dente', child: Text('Al Dente')),
              DropdownMenuItem(value: 'emulsified', child: Text('Emulsified')),
              DropdownMenuItem(value: 'caramelized', child: Text('Caramelized')),
            ],
            onChanged: (v) => setState(() => _stageLabel = v ?? 'target'),
          ),
          const SizedBox(height: 16),

          // Generate button
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _requestGuide,
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _loading ? 'Generating...' : 'Generate Guide Image',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Quick actions
          if (_guideResult != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.go(AppRoutes.sessionPath(widget.sessionId)),
                    child: const Text('Looks Right'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _requestGuide,
                    child: const Text('Another Stage'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// Taste Check Tab (Task 6.3)
// — Wired to real API via SessionApiService.tasteCheck()
// — Conversational style: prompt → chips/text → dimensions + recommendation
// =============================================================================

class TasteCheckTab extends StatefulWidget {
  final String sessionId;
  final ApiClient? apiClient;

  const TasteCheckTab({super.key, required this.sessionId, this.apiClient});

  @override
  State<TasteCheckTab> createState() => TasteCheckTabState();
}

class TasteCheckTabState extends State<TasteCheckTab> {
  final _descriptionController = TextEditingController();
  bool _loading = false;
  TasteCheckResponse? _apiResult;
  bool _showDiagnostic = false;
  bool _prompted = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _promptTaste() {
    setState(() {
      _prompted = true;
      _showDiagnostic = true;
      _apiResult = null;
      _error = null;
    });
  }

  Future<void> _submitTaste() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = widget.apiClient ?? context.read<ApiClient>();
      final sessionApi = SessionApiService(api: api);
      final response = await sessionApi.tasteCheck(
        widget.sessionId,
        diagnostic: description,
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _apiResult = response;
          _showDiagnostic = false;
          _prompted = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Taste check failed: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  void _selectChip(String text) {
    _descriptionController.text = text;
    _submitTaste();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Conversational prompt
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.restaurant, color: Colors.amber.shade800, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _prompted
                          ? 'Take a small spoonful and tell me — how does it taste?'
                          : 'Ready for a taste check? Tap below when you are.',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Prompt button (hidden once prompted)
          if (!_prompted && _apiResult == null)
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _promptTaste,
                icon: const Icon(Icons.restaurant, size: 24),
                label: const Text('Taste Check', style: TextStyle(fontSize: 18)),
              ),
            ),

          // Diagnostic input — conversational chips first, text fallback
          if (_showDiagnostic) ...[
            const SizedBox(height: 8),
            const Text(
              'Quick answers:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickTasteChip(
                  label: "It's flat",
                  onTap: () => _selectChip("It tastes flat and dull"),
                ),
                _QuickTasteChip(
                  label: "Too sharp",
                  onTap: () => _selectChip("It tastes sharp and too bright"),
                ),
                _QuickTasteChip(
                  label: "Something's missing",
                  onTap: () => _selectChip("Something is missing, it tastes one-note"),
                ),
                _QuickTasteChip(
                  label: "Too salty",
                  onTap: () => _selectChip("It's too salty"),
                ),
                _QuickTasteChip(
                  label: "Tastes great!",
                  onTap: () => _selectChip("It tastes great, well balanced"),
                ),
                _QuickTasteChip(
                  label: "Needs more heat",
                  onTap: () => _selectChip("It needs more spice or heat"),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Text input — always visible in conversational mode
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Or describe in your own words...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submitTaste,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Get Recommendation', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],

          // Error
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ),
          ],

          // Taste result with dimensions + recommendation
          if (_apiResult != null) ...[
            const SizedBox(height: 16),
            _TasteResultCard(result: _apiResult!),
            const SizedBox(height: 12),
            // Allow retasting
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _promptTaste,
                icon: const Icon(Icons.refresh),
                label: const Text('Taste Again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Taste check result card showing dimensions and recommendation.
class _TasteResultCard extends StatelessWidget {
  final TasteCheckResponse result;

  const _TasteResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recommendation header
            Row(
              children: [
                Icon(Icons.lightbulb, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Recommendation', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              result.recommendation,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),

            // Taste dimensions (if present)
            if (result.dimensions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Taste Balance', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...result.dimensions.entries.map((entry) {
                final value = entry.value.clamp(0.0, 1.0);
                final color = _dimensionColor(entry.key);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          _capitalize(entry.key),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: value,
                          backgroundColor: color.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation(color),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${(value * 100).toInt()}%',
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  static Color _dimensionColor(String dim) {
    return switch (dim) {
      'salt' => Colors.blue,
      'acid' => Colors.yellow.shade700,
      'sweet' => Colors.pink,
      'fat' => Colors.amber,
      'umami' => Colors.deepPurple,
      _ => Colors.grey,
    };
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

class _QuickTasteChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickTasteChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
    );
  }
}

// =============================================================================
// Recovery Tab (Task 6.4)
// — Wired to real API via SessionApiService.recover()
// — Instant-feel UX: immediateAction in large bold text first,
//   then explanation + alternatives
// =============================================================================

class RecoveryTab extends StatefulWidget {
  final String sessionId;
  final ApiClient? apiClient;

  const RecoveryTab({super.key, required this.sessionId, this.apiClient});

  @override
  State<RecoveryTab> createState() => RecoveryTabState();
}

class RecoveryTabState extends State<RecoveryTab> {
  final _errorController = TextEditingController();
  bool _loading = false;
  RecoveryResponse? _apiResult;
  String? _error;

  @override
  void dispose() {
    _errorController.dispose();
    super.dispose();
  }

  Future<void> _submitRecovery([String? quickIssue]) async {
    final desc = quickIssue ?? _errorController.text.trim();
    if (desc.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _apiResult = null;
    });

    try {
      final api = widget.apiClient ?? context.read<ApiClient>();
      final sessionApi = SessionApiService(api: api);
      final response = await sessionApi.recover(
        widget.sessionId,
        issue: desc,
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _apiResult = response;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Recovery failed: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Emergency header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 32, color: Colors.red.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Something went wrong? Tap a quick option or describe what happened.',
                    style: TextStyle(fontSize: 16, color: Colors.red.shade900, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick error chips — tapping submits immediately for instant-feel
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickErrorChip(
                label: 'Burnt',
                onTap: () => _submitRecovery('It burnt'),
              ),
              _QuickErrorChip(
                label: 'Overcooked',
                onTap: () => _submitRecovery('I overcooked it'),
              ),
              _QuickErrorChip(
                label: 'Sauce broke',
                onTap: () => _submitRecovery('The sauce broke/split'),
              ),
              _QuickErrorChip(
                label: 'Too salty',
                onTap: () => _submitRecovery('Added too much salt'),
              ),
              _QuickErrorChip(
                label: 'Stuck to pan',
                onTap: () => _submitRecovery('Food stuck to the pan'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Text input — visible (not behind expansion) for faster access
          TextField(
            controller: _errorController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Or describe in your own words...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),

          // Submit button — prominent for emergency
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : () => _submitRecovery(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.emergency, size: 24),
              label: Text(
                _loading ? 'Getting help...' : 'Help Me Recover',
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Error display
          if (_error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ),

          // Recovery result — instant-feel UX card
          if (_apiResult != null) _RecoveryResultCard(result: _apiResult!),
        ],
      ),
    );
  }
}

class _QuickErrorChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickErrorChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.flash_on, size: 16),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

/// Recovery result card with instant-feel UX:
/// - immediateAction shown in large bold text at top (red banner)
/// - explanation below
/// - alternatives as actionable items
class _RecoveryResultCard extends StatelessWidget {
  final RecoveryResponse result;

  const _RecoveryResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final severityColor = switch (result.severity) {
      'critical' => Colors.red.shade700,
      'high' => Colors.red.shade600,
      'medium' => Colors.orange.shade700,
      _ => Colors.amber.shade700,
    };

    return Card(
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Immediate action — large bold text, high contrast (instant-feel)
          if (result.immediateAction.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: severityColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.priority_high, color: Colors.white, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.immediateAction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Explanation
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.explanation.isNotEmpty) ...[
                  Text(
                    result.explanation,
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
                  ),
                ],

                // Alternative actions
                if (result.alternativeActions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Alternatives',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...result.alternativeActions.map((alt) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.arrow_right, size: 20, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                alt,
                                style: const TextStyle(fontSize: 15, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
