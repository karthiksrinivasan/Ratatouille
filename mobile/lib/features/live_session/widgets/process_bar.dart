import 'dart:async';
import 'package:flutter/material.dart';

/// A single cooking process from the backend.
class CookingProcess {
  final String processId;
  final String name;
  final int stepNumber;
  final String priority; // P0-P4
  final String state; // pending|in_progress|countdown|needs_attention|complete|passive
  final String? dueAt;
  final double? durationMinutes;
  final bool buddyManaged;
  final bool isParallel;

  CookingProcess({
    required this.processId,
    required this.name,
    required this.stepNumber,
    this.priority = 'P2',
    this.state = 'pending',
    this.dueAt,
    this.durationMinutes,
    this.buddyManaged = false,
    this.isParallel = false,
  });

  factory CookingProcess.fromJson(Map<String, dynamic> json) {
    return CookingProcess(
      processId: json['process_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      stepNumber: json['step_number'] as int? ?? 0,
      priority: json['priority'] as String? ?? 'P2',
      state: json['state'] as String? ?? 'pending',
      dueAt: json['due_at'] as String?,
      durationMinutes: (json['duration_minutes'] as num?)?.toDouble(),
      buddyManaged: json['buddy_managed'] as bool? ?? false,
      isParallel: json['is_parallel'] as bool? ?? false,
    );
  }

  /// Remaining seconds until due (null if no timer).
  int? get remainingSeconds {
    if (dueAt == null) return null;
    try {
      final due = DateTime.parse(dueAt!);
      final diff = due.difference(DateTime.now().toUtc()).inSeconds;
      return diff > 0 ? diff : 0;
    } catch (_) {
      return null;
    }
  }
}

/// Sticky process bar visible throughout live cooking.
///
/// Shows all active processes sorted by priority, with visual treatment
/// per state (countdown, needs_attention, passive, etc.).
/// Priority-based coloring: P0=red(pulsing), P1=amber, P2=primary,
/// P3/P4=grey. Countdown chips show mm:ss with <60s amber pulse.
class ProcessBar extends StatefulWidget {
  final List<CookingProcess> processes;
  final List<String> attentionNeeded;
  final CookingProcess? nextDue;
  final void Function(String processId)? onProcessTap;
  final void Function(String processId)? onDelegateTap;

  const ProcessBar({
    super.key,
    required this.processes,
    this.attentionNeeded = const [],
    this.nextDue,
    this.onProcessTap,
    this.onDelegateTap,
  });

  @override
  State<ProcessBar> createState() => _ProcessBarState();
}

class _ProcessBarState extends State<ProcessBar> {
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    // Tick every second to update countdown displays
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.processes.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.local_fire_department,
                  size: 18,
                  color: widget.attentionNeeded.isNotEmpty
                      ? Colors.red
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.processes.length} active',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                if (widget.nextDue != null)
                  _CountdownChip(process: widget.nextDue!),
              ],
            ),
          ),
          // Process chips
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: widget.processes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final process = widget.processes[index];
                return _ProcessChip(
                  process: process,
                  needsAttention: widget.attentionNeeded.contains(process.processId),
                  onTap: () => widget.onProcessTap?.call(process.processId),
                  onLongPress: () => widget.onDelegateTap?.call(process.processId),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Individual process chip with priority-based visual treatment.
///
/// P0 chips pulse continuously. Countdown chips show mm:ss.
/// At <60s remaining, chips switch to amber with pulse animation.
class _ProcessChip extends StatefulWidget {
  final CookingProcess process;
  final bool needsAttention;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ProcessChip({
    required this.process,
    required this.needsAttention,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<_ProcessChip> createState() => _ProcessChipState();
}

class _ProcessChipState extends State<_ProcessChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _updatePulse();
  }

  @override
  void didUpdateWidget(covariant _ProcessChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePulse();
  }

  void _updatePulse() {
    final shouldPulse = _shouldPulse;
    if (shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!shouldPulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }
  }

  bool get _shouldPulse {
    // P0 always pulses
    if (widget.process.priority == 'P0') return true;
    // Countdown with <60s remaining pulses
    if (widget.process.state == 'countdown') {
      final remaining = widget.process.remainingSeconds;
      if (remaining != null && remaining < 60) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _priorityColor(BuildContext context, String priority) {
    return switch (priority) {
      'P0' => Colors.red,
      'P1' => Colors.amber.shade700,
      'P2' => Theme.of(context).colorScheme.primary,
      'P3' => Colors.grey.shade500,
      'P4' => Colors.grey.shade400,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final (bgColor, fgColor, icon) = _stateStyle(context);
    final priorityColor = _priorityColor(context, widget.process.priority);

    Widget chip = Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: priorityColor, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fgColor),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  _label,
                  style: TextStyle(
                    color: fgColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.process.buddyManaged) ...[
                const SizedBox(width: 4),
                Icon(Icons.smart_toy, size: 14, color: fgColor),
              ],
            ],
          ),
        ),
      ),
    );

    // Wrap in pulse animation for P0 or <60s countdown
    if (_shouldPulse) {
      chip = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _pulseAnimation.value * 0.6 + 0.4, // Range: 0.4 - 1.0
            child: child,
          );
        },
        child: chip,
      );
    }

    return chip;
  }

  String get _label {
    if (widget.process.state == 'countdown') {
      final remaining = widget.process.remainingSeconds;
      if (remaining != null) {
        final min = remaining ~/ 60;
        final sec = remaining % 60;
        final shortName = widget.process.name.split(':').last.trim();
        final truncName = shortName.length > 8 ? shortName.substring(0, 8) : shortName;
        return '$truncName $min:${sec.toString().padLeft(2, '0')}';
      }
    }
    final shortName = widget.process.name.split(':').last.trim();
    return shortName.length > 15 ? '${shortName.substring(0, 15)}...' : shortName;
  }

  (Color, Color, IconData) _stateStyle(BuildContext context) {
    // For countdown with <60s, override to amber
    if (widget.process.state == 'countdown') {
      final remaining = widget.process.remainingSeconds;
      if (remaining != null && remaining < 60) {
        return (
          Colors.amber.shade100,
          Colors.amber.shade900,
          Icons.timer,
        );
      }
      return (
        Colors.orange.shade100,
        Colors.orange.shade800,
        Icons.timer,
      );
    }

    switch (widget.process.state) {
      case 'needs_attention':
        return (
          Colors.red.shade100,
          Colors.red.shade800,
          Icons.warning_amber_rounded,
        );
      case 'in_progress':
        return (
          Colors.blue.shade100,
          Colors.blue.shade800,
          Icons.play_circle_outline,
        );
      case 'passive':
        return (
          Colors.grey.shade200,
          Colors.grey.shade600,
          Icons.smart_toy_outlined,
        );
      case 'complete':
        return (
          Colors.green.shade100,
          Colors.green.shade800,
          Icons.check_circle_outline,
        );
      default: // pending
        return (
          Colors.grey.shade100,
          Colors.grey.shade600,
          Icons.hourglass_empty,
        );
    }
  }
}

/// Small countdown chip for the next-due timer.
class _CountdownChip extends StatelessWidget {
  final CookingProcess process;

  const _CountdownChip({required this.process});

  @override
  Widget build(BuildContext context) {
    final remaining = process.remainingSeconds;
    if (remaining == null) return const SizedBox.shrink();

    final min = remaining ~/ 60;
    final sec = remaining % 60;
    final isUrgent = remaining < 60;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isUrgent ? Colors.red.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            size: 14,
            color: isUrgent ? Colors.red.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            '$min:${sec.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isUrgent ? Colors.red.shade700 : Colors.orange.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
