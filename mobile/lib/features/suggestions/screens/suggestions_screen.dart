import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../shared/widgets/error_display.dart';
import '../../scan/models/scan_models.dart';
import '../../scan/providers/scan_provider.dart';

/// Dual-lane recipe suggestions screen.
///
/// Displays suggestions in two lanes (From Saved, Buddy Recipes) with
/// "Why this recipe?" expansion, match score, missing count, and start CTA.
class SuggestionsScreen extends StatelessWidget {
  const SuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<ScanProvider>(
      builder: (context, provider, _) {
        final suggestions = provider.suggestions;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Recipe Suggestions'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go(AppRoutes.scanReview),
            ),
          ),
          body: suggestions == null
              ? _buildEmptyState(theme, context)
              : _buildSuggestionsContent(suggestions, provider, theme, context),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, BuildContext context) {
    return ErrorDisplay(
      message: 'No suggestions available. Go back and scan your ingredients.',
      onRetry: () => context.go(AppRoutes.scan),
      retryLabel: 'Start New Scan',
    );
  }

  Widget _buildSuggestionsContent(
    SuggestionsResponse suggestions,
    ScanProvider provider,
    ThemeData theme,
    BuildContext context,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary
          _buildSummaryCard(suggestions, provider, theme),
          const SizedBox(height: 20),

          // Saved recipes lane
          if (suggestions.fromSaved.isNotEmpty) ...[
            _buildLaneHeader('From Your Saved Recipes', Icons.bookmark, theme),
            const SizedBox(height: 8),
            ...suggestions.fromSaved.map((s) => _SuggestionCard(
                  suggestion: s,
                  provider: provider,
                )),
            const SizedBox(height: 20),
          ],

          // Buddy recipes lane
          if (suggestions.buddyRecipes.isNotEmpty) ...[
            _buildLaneHeader('AI Buddy Recipes', Icons.auto_awesome, theme),
            const SizedBox(height: 8),
            ...suggestions.buddyRecipes.map((s) => _SuggestionCard(
                  suggestion: s,
                  provider: provider,
                )),
            const SizedBox(height: 20),
          ],

          // No suggestions at all
          if (suggestions.fromSaved.isEmpty &&
              suggestions.buddyRecipes.isEmpty)
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  Icon(Icons.search_off,
                      size: 64, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('No matching recipes found',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Try adding more ingredients or scanning again.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () => context.go(AppRoutes.scan),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan Again'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    SuggestionsResponse suggestions,
    ScanProvider provider,
    ThemeData theme,
  ) {
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.restaurant_menu, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Found ${suggestions.totalSuggestions} recipes matching '
                '${provider.confirmed.length} ingredients',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLaneHeader(String title, IconData icon, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleSmall),
      ],
    );
  }
}

/// Individual suggestion card with expandable "Why this recipe?" section.
class _SuggestionCard extends StatefulWidget {
  final RecipeSuggestion suggestion;
  final ScanProvider provider;

  const _SuggestionCard({
    required this.suggestion,
    required this.provider,
  });

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  bool _expanded = false;
  bool _loadingExplanation = false;

  Future<void> _toggleExplanation() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }

    setState(() {
      _loadingExplanation = true;
      _expanded = true;
    });

    await widget.provider.loadExplanation(widget.suggestion.suggestionId);

    if (mounted) {
      setState(() => _loadingExplanation = false);
    }
  }

  Future<void> _startSession() async {
    final result = await widget.provider.startSession(
      widget.suggestion.suggestionId,
    );

    if (result != null && mounted) {
      context.go(AppRoutes.sessionPath(result.sessionId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.suggestion;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + source label
                Row(
                  children: [
                    Expanded(
                      child:
                          Text(s.title, style: theme.textTheme.titleMedium),
                    ),
                    _buildSourceBadge(s, theme),
                  ],
                ),

                if (s.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    s.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 12),

                // Metadata chips
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _metaChip(
                      Icons.pie_chart,
                      '${s.matchPercent}% match',
                      theme,
                    ),
                    if (s.missingIngredients.isNotEmpty)
                      _metaChip(
                        Icons.shopping_cart_outlined,
                        '${s.missingIngredients.length} missing',
                        theme,
                      ),
                    if (s.estimatedTimeMin != null)
                      _metaChip(
                        Icons.timer_outlined,
                        '${s.estimatedTimeMin} min',
                        theme,
                      ),
                    if (s.difficulty != null)
                      _metaChip(
                        Icons.signal_cellular_alt,
                        s.difficulty!,
                        theme,
                      ),
                    if (s.cuisine != null)
                      _metaChip(Icons.public, s.cuisine!, theme),
                  ],
                ),

                const SizedBox(height: 12),

                // Inline explanation preview
                if (s.explanation.isNotEmpty)
                  Text(
                    s.explanation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // "Why this recipe?" expansion
          if (_expanded) _buildExpandedExplanation(theme),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _toggleExplanation,
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.help_outline,
                    size: 18,
                  ),
                  label: Text(
                    _expanded ? 'Less' : 'Why this recipe?',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      widget.provider.isLoading ? null : _startSession,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start Cooking'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceBadge(RecipeSuggestion s, ThemeData theme) {
    final isSaved = s.isSaved;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSaved
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        s.sourceLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isSaved
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedExplanation(ThemeData theme) {
    final explain = widget.provider.explain;

    if (_loadingExplanation || explain == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    return Container(
      color:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why this recipe?',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(explain.explanationFull, style: theme.textTheme.bodySmall),

          // Low confidence warnings
          if (explain.lowConfidenceWarnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber,
                    size: 16, color: Colors.orange),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Uncertain items: ${explain.lowConfidenceWarnings.join(", ")}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Assumptions
          if (explain.assumptions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    explain.assumptions.join('; '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
