import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/user_profile.dart';
import '../../core/state/providers.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/widgets/precise_field.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    if (profile == null) return const SizedBox.shrink();
    final weights = ref.watch(weightLogProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          // ── Identity card ───────────────────────────────────────
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  profile.name.isEmpty
                      ? '🙂'
                      : profile.name[0].toUpperCase(),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer),
                ),
              ),
              title: Text(profile.name,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${profile.age} y · ${profile.heightCm.round()} cm · ${profile.goal.label}'),
            ),
          ),
          const SizedBox(height: 12),

          // ── Account / cloud sync ────────────────────────────────
          const _AccountCard(),
          const SizedBox(height: 12),

          // ── Daily targets ───────────────────────────────────────
          Text('Daily targets',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _row('🔥', 'Calories', '${profile.kcalTarget.round()} kcal'),
                _row('🍗', 'Protein', '${profile.proteinTargetG.round()} g'),
                _row('🍚', 'Carbs', '${profile.carbsTargetG.round()} g'),
                _row('🥑', 'Fat', '${profile.fatTargetG.round()} g'),
                _row('💧', 'Water',
                    '${(profile.waterTargetMl / 1000).toStringAsFixed(1)} L'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Targets recalculate automatically when your weight or goal changes. The floor is never below 85% of your BMR.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          // ── Goal switcher ───────────────────────────────────────
          Text('Goal',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<Goal>(
            segments: Goal.values
                .map((g) => ButtonSegment(value: g, label: Text(g.label)))
                .toList(),
            selected: {profile.goal},
            onSelectionChanged: (s) => ref
                .read(profileProvider.notifier)
                .save(profile.copyWith(goal: s.first)),
          ),
          const SizedBox(height: 16),

          // ── Weight ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Weight',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              FilledButton.tonalIcon(
                onPressed: () => _logWeight(context, ref, profile.weightKg),
                icon: const Icon(Icons.monitor_weight_outlined, size: 18),
                label: const Text('Log weight'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: weights.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                        child: Text(
                            'No weigh-ins yet. Same time each morning gives the cleanest trend.')),
                  )
                : Column(
                    children: weights.reversed
                        .take(7)
                        .map((log) => ListTile(
                              dense: true,
                              leading: const Text('⚖️'),
                              title: Text(DateFormat('EEE, d MMM')
                                  .format(DateTime.parse(log.$1))),
                              trailing: Text(
                                  '${log.$2.toStringAsFixed(1)} kg',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 24),

          // ── About / reset ───────────────────────────────────────
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.cloud_off_outlined),
                  title: Text('Offline mode'),
                  subtitle: Text(
                      'All data lives on this device. Cloud sync, photo history and the full food database arrive with accounts.'),
                ),
                ListTile(
                  leading: Icon(Icons.restart_alt, color: scheme.error),
                  title: Text('Reset profile',
                      style: TextStyle(color: scheme.error)),
                  subtitle: const Text('Clears your setup and re-runs onboarding'),
                  onTap: () => _confirmReset(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String emoji, String label, String value) => ListTile(
        dense: true,
        leading: Text(emoji, style: const TextStyle(fontSize: 20)),
        title: Text(label),
        trailing:
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      );

  Future<void> _logWeight(
      BuildContext context, WidgetRef ref, double current) async {
    double value = current;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log weight'),
        content: StatefulBuilder(
          builder: (context, setState) => PreciseField(
            label: 'Weight',
            value: value,
            min: 35,
            max: 180,
            step: 0.1,
            decimals: 1,
            unit: 'kg',
            onChanged: (v) => setState(() => value = v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, value),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null) {
      await ref.read(weightLogProvider.notifier).log(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Weight logged — targets updated ✅')));
      }
    }
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset profile?'),
        content: const Text(
            'Your targets and setup will be cleared. Diary history stays on the device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(profileProvider.notifier).reset();
      if (context.mounted) context.go('/onboarding');
    }
  }
}

/// Cloud backup is opt-in. Signed out → an invitation; signed in → status,
/// manual sync, and sign-out (which never wipes local data).
class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final sync = ref.watch(syncEngineProvider);
    final scheme = Theme.of(context).colorScheme;

    if (!auth.signedIn) {
      return Card(
        color: scheme.primaryContainer,
        child: ListTile(
          leading: const Text('☁️', style: TextStyle(fontSize: 24)),
          title: const Text('Back up & sync',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text(
              'Sign in to save your diary to the cloud and sync across devices.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/auth'),
        ),
      );
    }

    final user = auth.user!;
    final subtitle = sync.syncing
        ? 'Syncing…'
        : sync.error != null
            ? 'Sync issue: ${sync.error}'
            : sync.lastSyncedAt != null
                ? 'Last synced ${_ago(sync.lastSyncedAt!)}'
                : 'Signed in';

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.cloud_done_rounded,
                  color: scheme.onPrimaryContainer),
            ),
            title: Text(user.email,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(subtitle,
                style: TextStyle(
                    color: sync.error != null ? scheme.error : null)),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: sync.syncing
                      ? null
                      : () =>
                          ref.read(syncEngineProvider.notifier).syncNow(),
                  icon: sync.syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => ref.read(authProvider.notifier).signOut(),
                  icon: Icon(Icons.logout, color: scheme.error),
                  label: Text('Sign out',
                      style: TextStyle(color: scheme.error)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return DateFormat('d MMM, HH:mm').format(t);
  }
}
