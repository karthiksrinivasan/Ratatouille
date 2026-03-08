import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/api_client.dart';

/// Full vision/guide/taste/recovery UX for live cooking sessions (Epic 6, Task 6.10).
///
/// Tabs:
///   1. Vision Check — capture frame, display confidence-tiered result
///   2. Guide Image — side-by-side or swipe comparison
///   3. Taste Check — prompted/diagnostic taste flow
///   4. Recovery — emergency-style recovery card
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
// Vision Check Tab
// =============================================================================

class VisionCheckTab extends StatefulWidget {
  final String sessionId;
  final ApiClient? apiClient;

  const VisionCheckTab({super.key, required this.sessionId, this.apiClient});

  @override
  State<VisionCheckTab> createState() => VisionCheckTabState();
}

class VisionCheckTabState extends State<VisionCheckTab> {
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _captureAndCheck() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // In a real app, this would capture from camera and upload.
    // For now, show a placeholder indicating the flow.
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _loading = false;
      _result = {
        'type': 'vision_result',
        'confidence': 'pending',
        'message': 'Point your camera at the food and tap capture to check doneness.',
        'tone': 'qualified',
      };
    });
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
            child: const Center(
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

          // Vision result card
          if (_result != null) VisionResultCard(result: _result!),
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

/// Displays vision check result with confidence badge and appropriate formatting.
class VisionResultCard extends StatelessWidget {
  final Map<String, dynamic> result;

  const VisionResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidence = result['confidence'] as String? ?? 'failed';
    final message = result['message'] as String? ?? '';
    final recommendation = result['recommendation'] as String?;
    final sensoryCheck = result['sensory_check'] as String?;

    final (badgeColor, badgeLabel) = switch (confidence) {
      'high' => (Colors.green, 'HIGH'),
      'medium' => (Colors.orange, 'MEDIUM'),
      'low' => (Colors.red.shade300, 'LOW'),
      _ => (Colors.grey, confidence.toUpperCase()),
    };

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Confidence badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Confidence',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Assessment message — minimum 16px for readability
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
            ),

            if (recommendation != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      recommendation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (sensoryCheck != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.hearing, size: 18, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sensory check: $sensoryCheck',
                        style: theme.textTheme.bodyMedium,
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
// Guide Image Tab
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
  Map<String, dynamic>? _guideResult;
  String _stageLabel = 'target';

  Future<void> _requestGuide() async {
    setState(() {
      _loading = true;
    });
    // Placeholder — in real app, calls API with camera frame
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _loading = false;
      _guideResult = {
        'type': 'guide_image',
        'image_url': null, // Would be a real URL from API
        'cue_overlays': ['Edges are light golden', 'Oil sheen visible'],
        'stage_label': _stageLabel,
      };
    });
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
              // Target state
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
                      child: _guideResult != null
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

          // Cue overlays
          if (_guideResult != null) ...[
            const Text(
              'Visual Cues',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...(_guideResult!['cue_overlays'] as List<dynamic>).map(
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
                    Text(cue as String, style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Stage selector
          DropdownButtonFormField<String>(
            value: _stageLabel,
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
                    onPressed: () {},
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
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Explain Cues'),
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
// Taste Check Tab
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
  Map<String, dynamic>? _result;
  bool _showDiagnostic = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _promptTaste() {
    setState(() {
      _result = {
        'type': 'taste_prompt',
        'message': 'Good moment to taste! Take a small spoonful and tell me how it is.',
        'dimensions': ['salt', 'acid', 'sweet', 'fat', 'umami'],
      };
      _showDiagnostic = true;
    });
  }

  Future<void> _submitTaste() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) return;

    setState(() => _loading = true);
    // Placeholder — in real app, calls API
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _loading = false;
      _result = {
        'type': 'taste_result',
        'message': 'Based on your description, try adding a squeeze of lemon for brightness. About half a lemon should do it.',
        'step': 1,
        'stage': 'mid',
      };
      _showDiagnostic = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Taste dimensions visual
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Five Taste Dimensions', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  const _TasteDimensionRow(label: 'Salt', icon: Icons.grain, color: Colors.blue),
                  const _TasteDimensionRow(label: 'Acid', icon: Icons.water_drop, color: Colors.yellow),
                  const _TasteDimensionRow(label: 'Sweet', icon: Icons.cake, color: Colors.pink),
                  const _TasteDimensionRow(label: 'Fat', icon: Icons.opacity, color: Colors.amber),
                  const _TasteDimensionRow(label: 'Umami', icon: Icons.restaurant_menu, color: Colors.deepPurple),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Prompt button
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _promptTaste,
              icon: const Icon(Icons.restaurant, size: 24),
              label: const Text('Taste Check', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 16),

          // Prompt result
          if (_result != null && _result!['type'] == 'taste_prompt') ...[
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.restaurant, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _result!['message'] as String,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Diagnostic input — quick chips are primary, text is optional fallback
          if (_showDiagnostic) ...[
            // Quick diagnostic buttons (voice-free, tap-based — primary interaction)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickTasteChip(label: "It's flat", onTap: () {
                  _descriptionController.text = "It tastes flat and dull";
                }),
                _QuickTasteChip(label: "Too sharp", onTap: () {
                  _descriptionController.text = "It tastes sharp and too bright";
                }),
                _QuickTasteChip(label: "Something's missing", onTap: () {
                  _descriptionController.text = "Something is missing, it tastes one-note";
                }),
                _QuickTasteChip(label: "Too salty", onTap: () {
                  _descriptionController.text = "It's too salty";
                }),
              ],
            ),
            const SizedBox(height: 12),
            // Optional text input (hidden behind expansion for voice-first UX)
            ExpansionTile(
              title: const Text('Or type your own description'),
              initiallyExpanded: false,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'How does it taste? (optional — use chips above or tell your buddy by voice)',
                      labelText: 'Your taste feedback',
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
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

          // Taste result
          if (_result != null && _result!['type'] == 'taste_result')
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Recommendation', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _result!['message'] as String,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TasteDimensionRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _TasteDimensionRow({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
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
// Recovery Tab
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
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _errorController.dispose();
    super.dispose();
  }

  Future<void> _submitRecovery() async {
    final desc = _errorController.text.trim();
    if (desc.isEmpty) return;

    setState(() => _loading = true);
    // Placeholder — in real app, calls /recover endpoint
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _loading = false;
      _result = {
        'type': 'recovery',
        'message': 'Take the pan off heat NOW.\n\nIt happens to everyone — garlic goes from golden to burnt fast.\n\nIt\'s a bit darker than ideal, but still usable.\n\nPick out the darkest pieces. The slight bitterness will actually complement the chili.',
        'step': 1,
        'techniques_affected': ['sauteing'],
      };
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    'Something went wrong? Describe what happened and I\'ll help you recover.',
                    style: TextStyle(fontSize: 16, color: Colors.red.shade900, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quick error chips (tap-based, voice-free — primary interaction)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickErrorChip(label: 'Burnt', onTap: () {
                _errorController.text = 'It burnt';
              }),
              _QuickErrorChip(label: 'Overcooked', onTap: () {
                _errorController.text = 'I overcooked it';
              }),
              _QuickErrorChip(label: 'Sauce broke', onTap: () {
                _errorController.text = 'The sauce broke/split';
              }),
              _QuickErrorChip(label: 'Too salty', onTap: () {
                _errorController.text = 'Added too much salt';
              }),
              _QuickErrorChip(label: 'Stuck to pan', onTap: () {
                _errorController.text = 'Food stuck to the pan';
              }),
            ],
          ),
          const SizedBox(height: 12),

          // Optional text input (hidden behind expansion for voice-first UX)
          ExpansionTile(
            title: const Text('Or describe in your own words'),
            initiallyExpanded: false,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _errorController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'What happened? (optional — use chips above or tell your buddy by voice)',
                    labelText: 'Describe the issue',
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Submit button — prominent for emergency
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _submitRecovery,
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

          // Recovery result — emergency card
          if (_result != null) RecoveryCard(result: _result!),
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

/// Emergency-style recovery card with "Do this now" at top.
class RecoveryCard extends StatelessWidget {
  final Map<String, dynamic> result;

  const RecoveryCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = result['message'] as String? ?? '';
    final techniques = (result['techniques_affected'] as List<dynamic>?) ?? [];

    // Split message into sections (paragraphs)
    final sections = message.split('\n\n').where((s) => s.trim().isNotEmpty).toList();

    return Card(
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top: immediate action — high contrast
          if (sections.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.priority_high, color: Colors.white, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sections.first,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Remaining sections
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 1; i < sections.length; i++) ...[
                  if (i > 1) const SizedBox(height: 12),
                  Text(
                    sections[i],
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
                  ),
                ],
                if (techniques.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: techniques
                        .map((t) => Chip(
                              avatar: const Icon(Icons.info_outline, size: 16),
                              label: Text(t.toString()),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
