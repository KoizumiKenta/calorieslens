import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/data/repositories.dart';
import '../../core/models/diary_entry.dart';
import '../../core/state/providers.dart';
import 'edit_entry_sheet.dart';

class DiaryScreen extends ConsumerWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final dateKey = dateKeyOf(date);
    final entries = ref.watch(diaryProvider(dateKey));
    final totals = ref.watch(dayTotalsProvider(dateKey));
    final profile = ref.watch(profileProvider);
    final scheme = Theme.of(context).colorScheme;

    final isToday = dateKey == dateKeyOf(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diary'),
        actions: [
          if (!isToday)
            TextButton(
              onPressed: () => ref
                  .read(selectedDateProvider.notifier)
                  .state = DateTime.now(),
              child: const Text('Today'),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Date navigator ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => ref
                      .read(selectedDateProvider.notifier)
                      .state = date.subtract(const Duration(days: 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    isToday
                        ? 'Today'
                        : DateFormat('EEE, d MMM yyyy').format(date),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: isToday
                      ? null
                      : () => ref
                          .read(selectedDateProvider.notifier)
                          .state = date.add(const Duration(days: 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),

          // ── Day summary ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${totals.kcal.round()}'
                      '${profile != null ? ' / ${profile.kcalTarget.round()}' : ''} kcal',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: scheme.onPrimaryContainer),
                    ),
                    Text(
                      'P ${totals.proteinG.round()} · C ${totals.carbsG.round()} · F ${totals.fatG.round()} g',
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Meals ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: Meal.values.map((meal) {
                final mealEntries =
                    entries.where((e) => e.meal == meal).toList();
                final mealKcal = mealEntries.fold<double>(
                    0, (sum, e) => sum + e.nutrition.kcal);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: Text(meal.emoji,
                              style: const TextStyle(fontSize: 22)),
                          title: Text(meal.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          subtitle: mealEntries.isEmpty
                              ? const Text('Nothing logged')
                              : Text('${mealKcal.round()} kcal'),
                          trailing: IconButton.filledTonal(
                            icon: const Icon(Icons.add),
                            tooltip: 'Add to ${meal.label}',
                            onPressed: () =>
                                context.push('/search?meal=${meal.name}'),
                          ),
                        ),
                        ...mealEntries.map(
                          (entry) => Dismissible(
                            key: ValueKey(entry.id),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) {
                              ref
                                  .read(diaryProvider(dateKey).notifier)
                                  .remove(entry.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('${entry.foodName} removed')),
                              );
                            },
                            background: Container(
                              color: scheme.errorContainer,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: Icon(Icons.delete_outline,
                                  color: scheme.onErrorContainer),
                            ),
                            child: ListTile(
                              dense: true,
                              onTap: () =>
                                  EditEntrySheet.show(context, entry),
                              leading: Text(entry.emoji,
                                  style: const TextStyle(fontSize: 18)),
                              title: Text(entry.foodName),
                              subtitle: Text(
                                '${entry.portionLabel ?? '${entry.grams.round()} g'}'
                                '${entry.source == EntrySource.scan ? ' · 📸 scanned' : ''}'
                                ' · tap to edit',
                              ),
                              trailing: Text(
                                  '${entry.nutrition.kcal.round()} kcal'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
