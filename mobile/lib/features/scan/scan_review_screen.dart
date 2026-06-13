import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/diary_entry.dart';
import '../../core/models/scan.dart';
import 'scan_controller.dart';

/// Review screen — the honest-numbers UX. Every detected item shows its
/// confidence band; tapping the chip reveals the model's reasoning verbatim;
/// tapping the row opens a portion editor. Totals show a range, not fake
/// precision.
class ScanReviewScreen extends ConsumerWidget {
  const ScanReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    final analysis = state.analysis;

    if (analysis == null) {
      // Reached via deep link or after logging — nothing to review.
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const Center(child: Text('No scan to review')),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final totals = analysis.totals;
    final (kcalLow, kcalHigh) = analysis.kcalRange;

    return Scaffold(
      appBar: AppBar(title: Text(analysis.dishName)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (state.imageBytes != null)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Image.memory(
                      state.imageBytes!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Text('🔍', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            analysis.overallNote,
                            style: TextStyle(
                                color: scheme.onSecondaryContainer,
                                fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...analysis.items.where((i) => !i.removed).map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ItemCard(
                          item: item,
                          onTap: () => _editPortion(context, ref, item),
                          onRemove: () => ref
                              .read(scanControllerProvider.notifier)
                              .setRemoved(item.id, true),
                        ),
                      ),
                    ),
                if (analysis.items.any((i) => i.removed))
                  TextButton.icon(
                    onPressed: () {
                      for (final i in analysis.items.where((i) => i.removed)) {
                        ref
                            .read(scanControllerProvider.notifier)
                            .setRemoved(i.id, false);
                      }
                    },
                    icon: const Icon(Icons.undo),
                    label: Text(
                        'Restore ${analysis.items.where((i) => i.removed).length} removed item(s)'),
                  ),
              ],
            ),
          ),

          // ── Totals + log bar ──────────────────────────────────────
          Material(
            elevation: 8,
            color: scheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${totals.kcal.round()} kcal',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            Text(
                              'likely ${kcalLow.round()}–${kcalHigh.round()} kcal',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        Text(
                          'P ${totals.proteinG.round()} · C ${totals.carbsG.round()} · F ${totals.fatG.round()} g',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: analysis.activeItems.isEmpty
                            ? null
                            : () => _logMeal(context, ref),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Log to diary'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPortion(
      BuildContext context, WidgetRef ref, ScanItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SingleChildScrollView(
        child: _PortionSheet(item: item),
      ),
    );
  }

  Future<void> _logMeal(BuildContext context, WidgetRef ref) async {
    final meal = await showModalBottomSheet<Meal>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Which meal is this?',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            ...Meal.values.map((m) => ListTile(
                  leading: Text(m.emoji, style: const TextStyle(fontSize: 22)),
                  title: Text(m.label),
                  onTap: () => Navigator.pop(sheetContext, m),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (meal == null || !context.mounted) return;

    final count =
        await ref.read(scanControllerProvider.notifier).logToDiary(meal);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Logged $count items to ${meal.label} ✅')),
    );
    context.go('/today');
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final ScanItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      child: Card(
        child: ListTile(
          onTap: onTap,
          leading: Text(item.emoji, style: const TextStyle(fontSize: 24)),
          title: Text(item.label, style: theme.textTheme.titleMedium),
          subtitle: Text('${item.grams.round()} g · tap to adjust',
              style: theme.textTheme.bodySmall),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _kcalText,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              _ConfidenceChip(item: item),
            ],
          ),
        ),
      ),
    );
  }

  String get _kcalText => switch (item.band) {
        ConfidenceBand.high ||
        ConfidenceBand.medium =>
          '${item.nutrition.kcal.round()} kcal',
        ConfidenceBand.low => '~${item.nutrition.kcal.round()} kcal',
      };
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.item});

  final ScanItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (label, fg, bg) = switch (item.band) {
      ConfidenceBand.high => (
          '${(item.confidence * 100).round()}%',
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
        ),
      ConfidenceBand.medium => (
          '${(item.confidence * 100).round()}% · range',
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        ),
      ConfidenceBand.low => (
          'check this',
          scheme.onErrorContainer,
          scheme.errorContainer,
        ),
    };

    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
      message: item.reasoning, // "Why this number?" — verbatim model reasoning
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
          semanticsLabel: 'Confidence $label. Tap for reasoning.',
        ),
      ),
    );
  }
}

/// Gram slider sheet. Edits are optimistic and recompute locally from
/// per-100g — no network round trip (mirrors reference scan_review_controller).
class _PortionSheet extends ConsumerStatefulWidget {
  const _PortionSheet({required this.item});

  final ScanItem item;

  @override
  ConsumerState<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends ConsumerState<_PortionSheet> {
  late double _grams = widget.item.grams;
  final _fixController = TextEditingController();
  bool _fixing = false;
  String? _fixError;

  @override
  void dispose() {
    _fixController.dispose();
    super.dispose();
  }

  Future<void> _fixWithAi() async {
    final note = _fixController.text.trim();
    if (note.isEmpty || _fixing) return;
    setState(() {
      _fixing = true;
      _fixError = null;
    });

    final error = await ref
        .read(scanControllerProvider.notifier)
        .refineItem(widget.item.id, note);

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _fixing = false;
        _fixError = error;
      });
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Item updated from your description ✨')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kcal = widget.item.per100g.forGrams(_grams).kcal;
    // Slider range: generous around the estimate so corrections are easy.
    final max = (widget.item.gramsHigh * 2.5).clamp(100.0, 1500.0);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.item.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.item.label,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'AI estimate: ${widget.item.gramsLow.round()}–${widget.item.gramsHigh.round()} g',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                '${_grams.round()} g · ${kcal.round()} kcal',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Slider(
              value: _grams.clamp(5, max),
              min: 5,
              max: max,
              onChanged: _fixing ? null : (v) => setState(() => _grams = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _fixing
                    ? null
                    : () {
                        ref
                            .read(scanControllerProvider.notifier)
                            .updateGrams(widget.item.id, _grams);
                        Navigator.pop(context);
                      },
                child: const Text('Save portion'),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            Text('Not quite right?',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Describe what it really is — the AI recalculates the nutrition from your words.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fixController,
              enabled: !_fixing,
              maxLength: 200,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _fixWithAi(),
              decoration: const InputDecoration(
                hintText: 'e.g. "air-fried chicken breast, no skin" or "milo kosong"',
                counterText: '',
              ),
            ),
            if (_fixError != null) ...[
              const SizedBox(height: 4),
              Text(_fixError!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _fixing ? null : _fixWithAi,
                icon: _fixing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high_rounded),
                label: Text(_fixing ? 'Recalculating…' : 'Fix with AI'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
