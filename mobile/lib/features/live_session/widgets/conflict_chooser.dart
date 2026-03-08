import 'dart:async';
import 'package:flutter/material.dart';

/// Full-width two-option chooser for P1 priority conflicts.
///
/// Designed for one-tap interaction under time pressure:
/// - Large tap targets (full width, 64px height)
/// - Clear visual distinction between options
/// - Visible countdown timer for timeout
class ConflictChooser extends StatefulWidget {
  final List<ConflictOption> options;
  final String message;
  final int timeoutSeconds;
  final void Function(String chosenProcessId) onChoice;
  final VoidCallback? onTimeout;

  const ConflictChooser({
    super.key,
    required this.options,
    required this.message,
    this.timeoutSeconds = 30,
    required this.onChoice,
    this.onTimeout,
  });

  @override
  State<ConflictChooser> createState() => _ConflictChooserState();
}

class _ConflictChooserState extends State<ConflictChooser>
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _countdownTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.timeoutSeconds;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _countdownTimer?.cancel();
          widget.onTimeout?.call();
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulseValue = 0.05 * _pulseController.value;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.red.withValues(alpha: 0.3 + pulseValue),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.1 + pulseValue),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with countdown
          Row(
            children: [
              const Icon(Icons.priority_high, color: Colors.red, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.message,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
              ),
              // Countdown badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _remainingSeconds <= 10
                      ? Colors.red.shade700
                      : Colors.red.shade400,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_remainingSeconds}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Option buttons — large tap targets
          for (var i = 0; i < widget.options.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _OptionButton(
              option: widget.options[i],
              label: i == 0 ? 'Handle A' : 'Handle B',
              color: i == 0 ? Colors.orange : Colors.blue,
              onTap: () => widget.onChoice(widget.options[i].processId),
            ),
          ],
          const SizedBox(height: 8),
          // Timeout explanation
          Text(
            'Auto-handling most urgent in ${_remainingSeconds}s',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.red.shade400,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single conflict option.
class ConflictOption {
  final String processId;
  final String name;
  final String urgency;

  ConflictOption({
    required this.processId,
    required this.name,
    required this.urgency,
  });

  factory ConflictOption.fromJson(Map<String, dynamic> json) {
    return ConflictOption(
      processId: json['process_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      urgency: json['urgency'] as String? ?? '',
    );
  }
}

/// Large, ergonomic option button for conflict resolution.
class _OptionButton extends StatelessWidget {
  final ConflictOption option;
  final String label;
  final MaterialColor color;
  final VoidCallback onTap;

  const _OptionButton({
    required this.option,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.shade600,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$label: ${option.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              option.urgency,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
