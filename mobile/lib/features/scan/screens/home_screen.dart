import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../core/auth_service.dart';
import '../../../shared/design_tokens.dart';

/// Home entry screen — the starting point for the cooking journey.
///
/// Provides clear entry points: "Cook from Fridge/Pantry" scan flow
/// and quick access to saved recipes.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthService>();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Profile button in top-right
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: Spacing.sm,
                  right: Spacing.pagePadding,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => context.go(AppRoutes.profile),
                    child: Chip(
                      avatar: Icon(
                        auth.isAnonymous
                            ? Icons.person_outline
                            : Icons.person,
                        size: 18,
                      ),
                      label: Text(
                        auth.isAnonymous
                            ? 'Guest'
                            : (auth.displayName ?? auth.email ?? 'Account'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.all(Spacing.pagePadding),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: Spacing.md),

                  // App title
                  Text(
                    'Ratatouille',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Your AI cooking companion',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: Spacing.xxl),

                  // Primary CTA — Scan from Fridge/Pantry
                  _EntryCard(
                    icon: Icons.camera_alt_rounded,
                    title: 'Cook from Fridge or Pantry',
                    subtitle:
                        'Snap photos of what you have and get recipe suggestions',
                    onTap: () => context.go(AppRoutes.scan),
                    isPrimary: true,
                  ),

                  const SizedBox(height: Spacing.md),

                  // Equal-priority — Cook Now (Seasoned Chef Buddy)
                  _EntryCard(
                    icon: Icons.mic_rounded,
                    title: 'Cook Now (Seasoned Chef Buddy)',
                    subtitle: 'No recipe needed — get live voice coaching instantly',
                    onTap: () => context.go(AppRoutes.cookNow),
                    isPrimary: true,
                  ),

                  const SizedBox(height: Spacing.md),

                  // Secondary — Browse Recipes
                  _EntryCard(
                    icon: Icons.menu_book_rounded,
                    title: 'Browse Recipes',
                    subtitle: 'View your saved recipes and start cooking',
                    onTap: () => context.go(AppRoutes.recipes),
                    isPrimary: false,
                  ),

                  const SizedBox(height: Spacing.xl),

                  // Version hint
                  Text(
                    'Hackathon MVP',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.md),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isPrimary;

  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: isPrimary ? Elevations.medium : Elevations.low,
      color: isPrimary ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Row(
            children: [
              Container(
                width: TouchTargets.handsBusy,
                height: TouchTargets.handsBusy,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: isPrimary
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
