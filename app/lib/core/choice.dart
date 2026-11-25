import 'package:flutter/material.dart';

import 'theme.dart';

/// Hick's Law selectors: instead of a dropdown (open, scan, pick, close), show
/// the few options directly as one-tap chips with a sensible default selected.

typedef Choice<T> = ({T value, String label});

/// Labelled group of single-select chips. Use for small option sets (≤ ~7).
class ChoiceGroup<T> extends StatelessWidget {
  const ChoiceGroup({super.key, required this.label, required this.options, required this.value, required this.onChanged});

  final String label;
  final List<Choice<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o.label),
            selected: o.value == value,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            selectedColor: BearchColors.accent.withValues(alpha: 0.18),
            labelStyle: o.value == value ? const TextStyle(color: BearchColors.accent, fontWeight: FontWeight.w700) : null,
            onSelected: (_) => onChanged(o.value),
          ),
      ]),
    ]);
  }
}

/// Team size as common presets (one tap) with a custom range revealed only on demand.
class TeamSizePicker extends StatefulWidget {
  const TeamSizePicker({super.key, required this.min, required this.max, required this.onChanged, this.limit = 10});

  final int min;
  final int max;
  final int limit;
  final void Function(int min, int max) onChanged;

  @override
  State<TeamSizePicker> createState() => _TeamSizePickerState();
}

class _TeamSizePickerState extends State<TeamSizePicker> {
  static const _presets = [(1, 1, 'Solo'), (2, 3, '2–3'), (3, 3, '3'), (3, 4, '3–4'), (3, 5, '3–5'), (4, 5, '4–5')];
  late bool _custom = !_presets.any((p) => p.$1 == widget.min && p.$2 == widget.max);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Team size', style: t.labelLarge),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in _presets)
          ChoiceChip(
            label: Text(p.$3),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            selected: !_custom && widget.min == p.$1 && widget.max == p.$2,
            selectedColor: BearchColors.accent.withValues(alpha: 0.18),
            onSelected: (_) {
              setState(() => _custom = false);
              widget.onChanged(p.$1, p.$2);
            },
          ),
        ChoiceChip(
          label: Text(_custom ? 'Custom: ${widget.min}–${widget.max}' : 'Custom…'),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selected: _custom,
          selectedColor: BearchColors.accent.withValues(alpha: 0.18),
          onSelected: (_) => setState(() => _custom = true),
        ),
      ]),
      if (_custom)
        RangeSlider(
          values: RangeValues(widget.min.toDouble(), widget.max.toDouble()),
          min: 1,
          max: widget.limit.toDouble(),
          divisions: widget.limit - 1,
          labels: RangeLabels('${widget.min}', '${widget.max}'),
          onChanged: (r) => widget.onChanged(r.start.round(), r.end.round()),
        ),
    ]);
  }
}
