import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/diary_entry.dart';
import '../../core/state/providers.dart';

/// Edit a logged diary entry: portion, meal, or delete. Nutrition rescales
/// from the entry's own snapshot (per-100g recovered), so history stays
/// consistent even if the food database changes later.
class EditEntrySheet extends ConsumerStatefulWidget {
  const EditEntrySheet({super.key, required this.entry});

  final DiaryEntry entry;

  /// Opens the sheet. Call from any screen showing diary entries.
  static Future<void> show(BuildContext context, DiaryEntry entry) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) =>
          SingleChildScrollView(child: EditEntrySheet(entry: entry)),
    );
  }

  @override
  ConsumerState<EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends ConsumerState<EditEntrySheet> {
  late double _grams = widget.entry.grams;
  late Meal _meal = widget.entry.meal;

  bool get _changed => _grams != widget.entry.grams || _meal != widget.entry.meal;

  Future<void> _save() async {
    final entry = widget.entry;
    final gramsChanged = _grams != entry.grams;
    final updated = entry.copyWith(
      meal: _meal,
      grams: _grams,
      nutrition: entry.per100g.forGrams(_grams),
      // "1 plate" stops being true once the amount changes.
      clearPortionLabel: gramsChanged,
      portionLabel: gramsChanged ? null : entry.portionLabel,
    );
    await ref.read(diaryProvider(entry.dateKey).notifier).update(updated);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${entry.foodName} updated ✅')),
    );
  }

  Future<void> _delete() async {
    final entry = widget.entry;
    await ref.read(diaryProvider(entry.dateKey).notifier).remove(entry.id);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${entry.foodName} removed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final nutrition = entry.per100g.forGrams(_grams);
    final max = (entry.grams * 3).clamp(150.0, 1500.0);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(entry.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(entry.foodName,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: _delete,
                  tooltip: 'Remove from diary',
                  icon: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                ),
              ],
            ),
            if (entry.source == EntrySource.scan)
              Text('Logged from a photo scan',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),

            Center(
              child: Text(
                '${_grams.round()} g · ${nutrition.kcal.round()} kcal',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Center(
              child: Text(
                'P ${nutrition.proteinG.round()} · C ${nutrition.carbsG.round()} · F ${nutrition.fatG.round()} g',
                style: theme.textTheme.bodySmall,
              ),
            ),
            Slider(
              value: _grams.clamp(5, max),
              min: 5,
              max: max,
              onChanged: (v) => setState(() => _grams = v),
            ),

            const SizedBox(height: 8),
            Text('Meal', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<Meal>(
              segments: Meal.values
                  .map((m) => ButtonSegment(value: m, label: Text(m.emoji)))
                  .toList(),
              selected: {_meal},
              onSelectionChanged: (s) => setState(() => _meal = s.first),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _changed ? _save : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
