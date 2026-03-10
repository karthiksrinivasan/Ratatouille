import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Full-screen overlay showing a guide image with camera PIP.
///
/// Slides up when the buddy sends a visual guide reference.
/// The camera preview shrinks to a picture-in-picture corner view
/// so the user can compare their work to the reference image.
/// Swipe down or tap "Looks Right" to dismiss.
class GuideImageOverlay extends StatelessWidget {
  final String imageUrl;
  final String caption;
  final List<String> visualCues;
  final VoidCallback onDismiss;
  final Widget cameraPip;

  const GuideImageOverlay({
    super.key,
    required this.imageUrl,
    required this.caption,
    this.visualCues = const [],
    required this.onDismiss,
    required this.cameraPip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 200) {
          onDismiss();
        }
      },
      child: Container(
        color: Colors.black87,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    Center(
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) =>
                            const CircularProgressIndicator(),
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 64),
                      ),
                    ),
                    // Visual cue annotations
                    ...visualCues.asMap().entries.map(
                          (entry) => Positioned(
                            left: 16,
                            top: 40.0 + entry.key * 28,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                entry.value,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                    // Camera PIP in bottom-right corner
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 120,
                          height: 160,
                          child: cameraPip,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  caption,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  height: 56,
                  width: 200,
                  child: FilledButton(
                    onPressed: onDismiss,
                    child: const Text(
                      'Looks Right',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
