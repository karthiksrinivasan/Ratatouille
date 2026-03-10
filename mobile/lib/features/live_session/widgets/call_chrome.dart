import 'package:flutter/material.dart';

/// FaceTime-style bottom call controls: Mute, Flip Camera, End Call.
///
/// All tap targets are 64px+ for hands-busy ergonomics during cooking.
class CallChrome extends StatelessWidget {
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onFlipCamera;
  final VoidCallback onEndCall;

  const CallChrome({
    super.key,
    required this.isMuted,
    required this.onToggleMute,
    required this.onFlipCamera,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      color: Colors.black38,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CallButton(
            icon: isMuted ? Icons.mic_off : Icons.mic,
            label: isMuted ? 'Unmute' : 'Mute',
            onTap: onToggleMute,
            color: isMuted ? Colors.red : Colors.white,
          ),
          _CallButton(
            icon: Icons.flip_camera_ios,
            label: 'Flip',
            onTap: onFlipCamera,
          ),
          _CallButton(
            icon: Icons.call_end,
            label: 'End',
            onTap: onEndCall,
            color: Colors.red,
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool filled;

  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? color : Colors.white24,
            ),
            child: Icon(
              icon,
              color: filled ? Colors.white : color,
              size: 28,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
