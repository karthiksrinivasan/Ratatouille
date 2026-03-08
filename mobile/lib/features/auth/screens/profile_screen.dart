import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/router.dart';
import '../../../core/auth_service.dart';
import '../../../shared/design_tokens.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = false;

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await context.read<AuthService>().signOut();
      if (mounted) context.go(AppRoutes.login);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign out failed')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await context.read<AuthService>().deleteAccount();
      if (mounted) context.go(AppRoutes.login);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete account. You may need to sign in again first.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editDisplayName() async {
    final auth = context.read<AuthService>();
    final controller = TextEditingController(text: auth.displayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Display Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Enter your name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || !mounted) return;

    try {
      await auth.updateDisplayName(newName);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update name')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final isGuest = auth.isAnonymous;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Spacing.pagePadding),
              children: [
                const SizedBox(height: Spacing.lg),

                // Avatar
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      isGuest ? Icons.person_outline : Icons.person,
                      size: 48,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.md),

                // Account type badge
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: isGuest
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      isGuest ? 'Guest Account' : 'Registered',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isGuest
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: Spacing.xl),

                // Prompt guest to sign up
                if (isGuest) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.lg),
                      child: Column(
                        children: [
                          Text(
                            'Create an account to save your recipes and cooking history',
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Spacing.md),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => context.go(AppRoutes.signup),
                              child: const Text('Create Account'),
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => context.go(AppRoutes.login),
                              child: const Text('Sign In'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Display name
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Display Name'),
                    subtitle: Text(auth.displayName ?? 'Not set'),
                    trailing: const Icon(Icons.edit_outlined, size: 20),
                    onTap: _editDisplayName,
                  ),
                  const Divider(),

                  // Email
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Email'),
                    subtitle: Text(auth.email ?? 'Not set'),
                  ),
                  const Divider(),

                  // UID (debug info)
                  ListTile(
                    leading: const Icon(Icons.fingerprint),
                    title: const Text('User ID'),
                    subtitle: Text(
                      user?.uid ?? 'N/A',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],

                const SizedBox(height: Spacing.xxl),

                // Sign out
                if (auth.isSignedIn && !isGuest)
                  OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                  ),

                if (auth.isSignedIn && !isGuest) ...[
                  const SizedBox(height: Spacing.md),
                  TextButton(
                    onPressed: _deleteAccount,
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete Account'),
                  ),
                ],

                // Guest sign out (just clears anon session)
                if (isGuest)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.lg),
                    child: TextButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                    ),
                  ),
              ],
            ),
    );
  }
}
