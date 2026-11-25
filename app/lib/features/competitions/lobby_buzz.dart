import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Eye-catching "open lobbies" strip on a competition card: accent tint, a
/// live pulsing dot and a teaser line, so students tap in to see who's there.
class LobbyBuzz extends StatelessWidget {
  const LobbyBuzz({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final live = count > 0;
    final color = live ? BearchColors.accent : BearchColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.05)]),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        if (live) const RepaintBoundary(child: _LiveDot()) else Icon(Icons.flag_rounded, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: live ? '$count open ${count == 1 ? 'lobby' : 'lobbies'}' : 'No lobby yet',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              TextSpan(text: live ? ' · looking for teammates' : ' · be the first to start one'),
            ]),
            style: t.labelMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(live ? 'Peek' : 'Start', style: t.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
        Icon(Icons.chevron_right_rounded, size: 18, color: color),
      ]),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  // A few pulses to catch the eye, then rest: no endless ticker per card.
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_c.isAnimating && _c.value == 0 && !MediaQuery.disableAnimationsOf(context)) _c.repeat(count: 4);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 16,
        height: 16,
        child: Stack(alignment: Alignment.center, children: [
          ScaleTransition(
            scale: Tween(begin: 0.4, end: 1.0).animate(_c),
            child: FadeTransition(
              opacity: Tween(begin: 0.6, end: 0.0).animate(_c),
              child: const DecoratedBox(
                decoration: BoxDecoration(color: BearchColors.accent, shape: BoxShape.circle),
                child: SizedBox.expand(),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(color: BearchColors.accent, shape: BoxShape.circle),
            child: SizedBox(width: 8, height: 8),
          ),
        ]),
      );
}
