import 'package:flutter/material.dart';

/// Install a global error widget builder that shows a user-friendly fallback
/// instead of the default red error screen. Call before [runApp].
void setupErrorBoundary() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return _ErrorFallback(error: details.exception, onRetry: null);
  };
}

/// A widget that catches errors reported by its children and shows a
/// fallback UI with an optional retry button.
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(Object error, VoidCallback retry)? errorBuilder;

  const ErrorBoundary({super.key, required this.child, this.errorBuilder});

  @override
  State<ErrorBoundary> createState() => ErrorBoundaryState();
}

class ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;

  void reportError(Object error) {
    setState(() => _error = error);
  }

  void _reset() => setState(() => _error = null);

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_error!, _reset);
      }
      return _ErrorFallback(error: _error!, onRetry: _reset);
    }
    return widget.child;
  }
}

class _ErrorFallback extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const _ErrorFallback({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Something went wrong', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
