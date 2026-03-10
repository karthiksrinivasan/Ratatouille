import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/error_display.dart';
import '../providers/scan_provider.dart';

/// Fridge/pantry scan flow — capture entry screen.
///
/// Provides source selector (Fridge | Pantry), mode selector (Photos | Video),
/// capture guidance, and image grid before uploading.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickFromCamera(ScanProvider provider) async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (image != null) {
      provider.addImage(File(image.path));
    }
  }

  Future<void> _pickFromGallery(ScanProvider provider) async {
    final images = await _picker.pickMultiImage(imageQuality: 85);
    for (final image in images) {
      if (provider.selectedImages.length >= 6) break;
      provider.addImage(File(image.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<ScanProvider>(
      builder: (context, provider, _) {
        // If we're past review phase, navigate to ingredient review
        if (provider.phase == ScanPhase.reviewing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.go(AppRoutes.scanReview);
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Scan Your Kitchen'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go(AppRoutes.recipes),
            ),
          ),
          body: provider.isLoading
              ? _buildLoadingState(provider, theme)
              : provider.error != null
                  ? ErrorDisplay(
                      message: provider.error!,
                      onRetry: () {
                        provider.clearError();
                      },
                    )
                  : _buildCaptureUI(provider, theme),
        );
      },
    );
  }

  Widget _buildLoadingState(ScanProvider provider, ThemeData theme) {
    final message = provider.phase == ScanPhase.uploading
        ? 'Uploading images...'
        : 'Detecting ingredients with AI...';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(message, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'This may take a few seconds',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureUI(ScanProvider provider, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Source selector
          _buildSourceSelector(provider, theme),
          const SizedBox(height: 20),

          // Capture guidance
          _buildCaptureGuidance(provider, theme),
          const SizedBox(height: 20),

          // Image grid
          if (provider.selectedImages.isNotEmpty) ...[
            _buildImageGrid(provider, theme),
            const SizedBox(height: 16),
          ],

          // Capture buttons
          _buildCaptureButtons(provider, theme),
          const SizedBox(height: 24),

          // Upload button
          if (provider.selectedImages.length >= 2)
            FilledButton.icon(
              onPressed: () => provider.uploadAndDetect(),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Scan Ingredients'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

          const SizedBox(height: 12),

          // Manual entry fallback
          OutlinedButton.icon(
            onPressed: () {
              // Go to review with empty detected list for manual entry
              provider.reset();
              context.go(AppRoutes.scanReview);
            },
            icon: const Icon(Icons.edit_note),
            label: const Text('Enter ingredients manually'),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSelector(ScanProvider provider, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What are you scanning?',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'fridge',
                  label: Text('Fridge'),
                  icon: Icon(Icons.kitchen),
                ),
                ButtonSegment(
                  value: 'pantry',
                  label: Text('Pantry'),
                  icon: Icon(Icons.shelves),
                ),
              ],
              selected: {provider.source},
              onSelectionChanged: (s) => provider.setSource(s.first),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptureGuidance(ScanProvider provider, ThemeData theme) {
    final count = provider.selectedImages.length;
    final minMet = count >= 2;

    return Card(
      color: minMet
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              minMet ? Icons.check_circle : Icons.info_outline,
              color: minMet
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                minMet
                    ? '$count/6 photos selected — ready to scan!'
                    : '$count/6 photos (minimum 2 required)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: minMet
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: minMet ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid(ScanProvider provider, ThemeData theme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: provider.selectedImages.length,
      itemBuilder: (context, index) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                provider.selectedImages[index],
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => provider.removeImage(index),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: theme.colorScheme.onError,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCaptureButtons(ScanProvider provider, ThemeData theme) {
    final canAdd = provider.selectedImages.length < 6;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canAdd ? () => _pickFromCamera(provider) : null,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Camera'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canAdd ? () => _pickFromGallery(provider) : null,
            icon: const Icon(Icons.photo_library),
            label: const Text('Gallery'),
          ),
        ),
      ],
    );
  }
}
