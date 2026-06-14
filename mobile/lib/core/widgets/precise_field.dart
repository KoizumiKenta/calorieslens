import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A precise numeric input: tap the value to type an exact number, use the
/// −/+ buttons for fine steps, or drag the slider for a coarse sweep.
///
/// Replaces bare [Slider]s for weight, height, age, and food grams — sliders
/// alone can't hit an exact value on a phone-width track.
class PreciseField extends StatelessWidget {
  const PreciseField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.unit = '',
    this.decimals = 0,
    this.showSlider = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;

  /// Increment applied by the −/+ buttons.
  final double step;
  final String unit;

  /// Display precision; also gates decimal entry in the type dialog.
  final int decimals;
  final bool showSlider;
  final ValueChanged<double> onChanged;

  String _fmt(double v) =>
      decimals == 0 ? v.round().toString() : v.toStringAsFixed(decimals);

  double _clamp(double v) => v.clamp(min, max).toDouble();

  /// Snap to the field's precision so stepping/dragging never leaves a long
  /// fractional tail (e.g. 72.3000001 kg).
  double _round(double v) {
    if (decimals == 0) return v.roundToDouble();
    final f = math.pow(10, decimals).toDouble();
    return (v * f).roundToDouble() / f;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = _clamp(value);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: theme.textTheme.titleMedium),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _typeValue(context),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_fmt(v),
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.primary)),
                      if (unit.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(unit,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                      const SizedBox(width: 2),
                      Icon(Icons.edit, size: 14, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                tooltip: '−$step',
                onPressed:
                    v <= min ? null : () => onChanged(_clamp(_round(v - step))),
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: showSlider
                    ? Slider(
                        value: v,
                        min: min,
                        max: max,
                        onChanged: (nv) => onChanged(_round(nv)),
                      )
                    : const SizedBox(width: 12),
              ),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                tooltip: '+$step',
                onPressed:
                    v >= max ? null : () => onChanged(_clamp(_round(v + step))),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _typeValue(BuildContext context) async {
    final controller = TextEditingController(text: _fmt(_clamp(value)));
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: controller.text.length);

    double? parse() => double.tryParse(controller.text.trim());

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              TextInputType.numberWithOptions(decimal: decimals > 0),
          inputFormatters: [
            decimals > 0
                ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                : FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            suffixText: unit,
            helperText: 'Range ${_fmt(min)}–${_fmt(max)} $unit',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, parse()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, parse()),
              child: const Text('Set')),
        ],
      ),
    );
    controller.dispose();
    if (result != null) onChanged(_clamp(_round(result)));
  }
}
