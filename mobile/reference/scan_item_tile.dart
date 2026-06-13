import 'package:flutter/material.dart';

import '../../domain/scan_result.dart';

/// One detected food in the review card. Embodies the honest-numbers UX:
/// ≥90% confidence shows a plain value, 70–89% shows the range, <70% asks
/// the user to check. Tapping the chip reveals the model's reasoning.
class ScanItemTile extends StatelessWidget {
  const ScanItemTile({
    super.key,
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
      background: _removeBackground(theme),
      child: ListTile(
        onTap: onTap,
        title: Text(item.label, style: theme.textTheme.titleMedium),
        subtitle: Text(
          item.servingLabel != null
              ? '${item.servingLabel} · ${item.grams.round()} g'
              : '${item.grams.round()} g',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _kcalText,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            _ConfidenceChip(item: item),
          ],
        ),
      ),
    );
  }

  String get _kcalText => switch (item.band) {
        ConfidenceBand.high || ConfidenceBand.medium => '${item.nutrition.kcal.round()} kcal',
        ConfidenceBand.low => '~${item.nutrition.kcal.round()} kcal',
      };

  Widget _removeBackground(ThemeData theme) => Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      );
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
      ConfidenceBand.low => ('check this', scheme.onErrorContainer, scheme.errorContainer),
    };

    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
      message: item.reasoning, // "Why this number?" — verbatim model reasoning
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
          semanticsLabel: 'Confidence $label. Tap for reasoning.',
        ),
      ),
    );
  }
}
