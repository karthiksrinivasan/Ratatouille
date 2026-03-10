import 'package:flutter/material.dart';

/// Displays buddy speech as captions overlaid on the camera feed.
///
/// Shows connection state (e.g. "Listening...") and the latest buddy
/// message text with a fade-out animation after 5 seconds.
class BuddyCaption extends StatefulWidget {
  final String text;
  final String connectionState;

  const BuddyCaption({
    super.key,
    required this.text,
    this.connectionState = 'Listening...',
  });

  @override
  State<BuddyCaption> createState() => _BuddyCaptionState();
}

class _BuddyCaptionState extends State<BuddyCaption>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.value = 1.0;
  }

  @override
  void didUpdateWidget(BuddyCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text && widget.text.isNotEmpty) {
      _fadeController.value = 1.0;
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _fadeController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // D6.11: Semi-transparent dark gradient behind caption for bright-kitchen readability
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.black.withValues(alpha: 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.connectionState,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14, // D6.11: bumped from 13 to 14
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          FadeTransition(
            opacity: _fadeAnimation,
            child: Text(
              widget.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600, // D6.11: bolder for readability
                height: 1.4,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 4,
                    color: Colors.black87,
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
