import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/data/repositories.dart';
import '../../core/models/diary_entry.dart';
import '../../core/state/providers.dart';
import '../diary/edit_entry_sheet.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    if (profile == null) return const SizedBox.shrink();

    final dateKey = dateKeyOf(DateTime.now());
    final totals = ref.watch(dayTotalsProvider(dateKey));
    final entries = ref.watch(diaryProvider(dateKey));
    final waterMl = ref.watch(waterProvider(dateKey));
    final scheme = Theme.of(context).colorScheme;

    final remaining = profile.kcalTarget - totals.kcal;
    final streak = ref.watch(streakProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hi ${profile.name} 👋'),
            Text(
              DateFormat('EEEE, d MMMM').format(DateTime.now()),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        toolbarHeight: 72,
        actions: [
          if (streak > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _StreakChip(days: streak),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          // ── Calorie ring ────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      tween: Tween(
                        begin: 0.0,
                        end: profile.kcalTarget <= 0
                            ? 0.0
                            : (totals.kcal / profile.kcalTarget)
                                .clamp(0.0, 1.0),
                      ),
                      builder: (context, animatedProgress, child) => CustomPaint(
                        painter: _RingPainter(
                          progress: animatedProgress,
                          over: totals.kcal > profile.kcalTarget,
                          trackColor: scheme.surfaceContainerHighest,
                          ringColor: totals.kcal > profile.kcalTarget
                              ? scheme.error
                              : scheme.primary,
                        ),
                        child: child,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${totals.kcal.round()}',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text('of ${profile.kcalTarget.round()} kcal',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          remaining >= 0
                              ? '${remaining.round()} kcal left'
                              : '${(-remaining).round()} kcal over',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: remaining >= 0
                                      ? scheme.primary
                                      : scheme.error),
                        ),
                        const SizedBox(height: 12),
                        _macroBar(context, 'Protein', totals.proteinG,
                            profile.proteinTargetG, scheme.tertiary),
                        _macroBar(context, 'Carbs', totals.carbsG,
                            profile.carbsTargetG, scheme.secondary),
                        _macroBar(context, 'Fat', totals.fatG,
                            profile.fatTargetG, scheme.error),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Quick actions ───────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _actionCard(
                  context,
                  icon: Icons.camera_alt_rounded,
                  label: 'Scan meal',
                  color: scheme.primaryContainer,
                  onTap: () => context.push('/scan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionCard(
                  context,
                  icon: Icons.search_rounded,
                  label: 'Search food',
                  color: scheme.secondaryContainer,
                  onTap: () => context.push('/search'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Water ───────────────────────────────────────────────
          _WaterCard(
            waterMl: waterMl,
            drinksMl: ref.watch(drinksHydrationProvider(dateKey)),
            targetMl: profile.waterTargetMl,
            onAdjust: (delta) =>
                ref.read(waterProvider(dateKey).notifier).adjust(delta),
          ),
          const SizedBox(height: 20),

          // ── Today's meals ───────────────────────────────────────
          Text('Today\'s meals',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text('🍽️', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text('Nothing logged yet',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Tap the camera and snap your next meal — it takes 5 seconds.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          else
            ...Meal.values.map((meal) {
              final mealEntries =
                  entries.where((e) => e.meal == meal).toList();
              if (mealEntries.isEmpty) return const SizedBox.shrink();
              final mealKcal = mealEntries.fold<double>(
                  0, (sum, e) => sum + e.nutrition.kcal);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        ListTile(
                          dense: true,
                          leading: Text(meal.emoji,
                              style: const TextStyle(fontSize: 20)),
                          title: Text(meal.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${mealKcal.round()} kcal',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 4),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Add to ${meal.label}',
                                icon: const Icon(Icons.add_circle_outline,
                                    size: 20),
                                onPressed: () => context
                                    .push('/search?meal=${meal.name}'),
                              ),
                            ],
                          ),
                        ),
                        ...mealEntries.map((e) => ListTile(
                              dense: true,
                              onTap: () => EditEntrySheet.show(context, e),
                              leading: Text(e.emoji,
                                  style: const TextStyle(fontSize: 18)),
                              title: Text(e.foodName),
                              subtitle: Text(
                                  '${e.portionLabel ?? '${e.grams.round()} g'} · tap to edit'),
                              trailing:
                                  Text('${e.nutrition.kcal.round()} kcal'),
                            )),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _macroBar(BuildContext context, String label, double value,
      double target, Color color) {
    final progress = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text('${value.round()} / ${target.round()} g',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0.0, end: progress),
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              color: color,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(BuildContext context,
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap}) {
    return Card(
      color: color,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hydration with actual feedback: progress toward the personal target,
/// auto-credit from logged drinks, user-defined vessels for one-tap logging,
/// a celebratory done-state, and a "why this number" explainer.
class _WaterCard extends ConsumerWidget {
  const _WaterCard({
    required this.waterMl,
    required this.drinksMl,
    required this.targetMl,
    required this.onAdjust,
  });

  final int waterMl;
  final double drinksMl;
  final double targetMl;
  final void Function(int deltaMl) onAdjust;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalMl = waterMl + drinksMl;
    final progress = targetMl <= 0 ? 0.0 : (totalMl / targetMl).clamp(0.0, 1.0);
    final done = totalMl >= targetMl;
    final glassesLeft = ((targetMl - totalMl) / 250).ceil();
    final vessels = ref.watch(vesselsProvider);

    return Card(
      color: done ? scheme.tertiaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('💧', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text('Water', style: theme.textTheme.titleMedium),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.info_outline,
                      size: 18, color: scheme.onSurfaceVariant),
                  tooltip: 'Why this target?',
                  onPressed: () => _showInfo(context),
                ),
                const Spacer(),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  onPressed: waterMl <= 0 ? null : () => onAdjust(-250),
                  icon: const Icon(Icons.remove),
                  tooltip: 'Undo 250 ml',
                ),
              ],
            ),
            const SizedBox(height: 8),
            // One-tap vessels: tap to log, long-press to remove, + to add.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // Custom chip so one InkWell owns BOTH tap (log) and
                // long-press (remove) — ActionChip swallows the long-press.
                for (var i = 0; i < vessels.length; i++)
                  Material(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onAdjust(vessels[i].ml),
                      onLongPress: () =>
                          _confirmRemoveVessel(context, ref, i, vessels[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(vessels[i].emoji),
                            const SizedBox(width: 6),
                            Text('+${vessels[i].ml}'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('vessel'),
                  onPressed: () => _addVessel(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Tap to log · hold a vessel to remove',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: done ? scheme.tertiary : scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            Text(
              done
                  ? 'Target hit — ${(totalMl / 1000).toStringAsFixed(2)} L today. Well hydrated! 🎉'
                  : '${(totalMl / 1000).toStringAsFixed(2)} of ${(targetMl / 1000).toStringAsFixed(1)} L · ${(progress * 100).round()}% — about $glassesLeft glass${glassesLeft == 1 ? '' : 'es'} to go',
              style: theme.textTheme.bodySmall?.copyWith(
                color: done ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
                fontWeight: done ? FontWeight.w600 : null,
              ),
            ),
            if (drinksMl > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${(waterMl / 1000).toStringAsFixed(2)} L water + ${(drinksMl / 1000).toStringAsFixed(2)} L from drinks in your diary',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: done
                          ? scheme.onTertiaryContainer
                          : scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addVessel(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final mlController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add your vessel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                  labelText: 'Name', hintText: 'e.g. Office bottle'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mlController,
              decoration: const InputDecoration(
                  labelText: 'Size (ml)', hintText: 'e.g. 750'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (added == true) {
      final ml = int.tryParse(mlController.text.trim());
      if (ml != null && ml > 0 && ml <= 3000) {
        final name = nameController.text.trim();
        await ref
            .read(vesselsProvider.notifier)
            .add(name.isEmpty ? '$ml ml' : name, ml);
      }
    }
    nameController.dispose();
    mlController.dispose();
  }

  Future<void> _confirmRemoveVessel(BuildContext context, WidgetRef ref,
      int index, WaterVessel vessel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove "${vessel.label}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(vesselsProvider.notifier).removeAt(index);
    }
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('💧 Your water target'),
        content: Text(
          'Your target is 33 ml per kg of body weight '
          '(capped between 1.5 and 4 L) — about ${(targetMl / 1000).toStringAsFixed(1)} L for you. '
          'It updates automatically when your weight changes.\n\n'
          'Why it matters while losing weight: water supports the kidneys '
          'in clearing the by-products of fat metabolism, helps separate thirst '
          'from hunger (they feel similar), and replaces what you lose to '
          'exercise and hot weather.\n\n'
          'Drinks you log in your diary count automatically — a teh tarik or '
          'Milo credits ~90% of its volume here, so don\'t add it again with '
          'the buttons. The chips are for plain water: tap your vessel once '
          'per pour, long-press to remove one, or add your own bottle size. '
          'Drink more on training days and in hot weather.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// Daily logging streak — the cheap retention loop. Pops in with a quick
/// scale so hitting a new day's first log feels rewarding.
class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      key: ValueKey(days),
      duration: const Duration(milliseconds: 350),
      curve: Curves.elasticOut,
      tween: Tween(begin: 0.7, end: 1.0),
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              '$days',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.over,
    required this.trackColor,
    required this.ringColor,
  });

  final double progress;
  final bool over;
  final Color trackColor;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = ringColor
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      ring,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.ringColor != ringColor;
}
