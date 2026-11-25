import 'package:flutter/material.dart';

import 'glass.dart';

/// Gentle pulse used by all skeletons. One controller per skeleton group and a
/// plain FadeTransition: no shader, no blur, cheap to render.
class SkeletonPulse extends StatefulWidget {
  const SkeletonPulse({super.key, required this.child});

  final Widget child;

  @override
  State<SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<SkeletonPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final Animation<double> _opacity = Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: RepaintBoundary(child: FadeTransition(opacity: _opacity, child: widget.child)),
      );
}

/// Grey placeholder block (text line, avatar, chip, chart...).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.10 : 0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A glass card shaped like a list item: optional avatar, title + text lines, chips.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2, this.avatar = false, this.chips = false});

  final int lines;
  final bool avatar;
  final bool chips;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (avatar) ...[const SkeletonBox(width: 40, height: 40, radius: 20), const SizedBox(width: 12)],
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FractionallySizedBox(widthFactor: 0.6, child: SkeletonBox(height: 16)),
              SizedBox(height: 8),
              FractionallySizedBox(widthFactor: 0.4, child: SkeletonBox(height: 12)),
            ]),
          ),
        ]),
        for (var i = 0; i < lines; i++) ...[
          const SizedBox(height: 10),
          FractionallySizedBox(widthFactor: i == lines - 1 ? 0.7 : 1, child: const SkeletonBox(height: 12)),
        ],
        if (chips) ...[
          const SizedBox(height: 12),
          const Row(children: [
            SkeletonBox(width: 70, height: 22, radius: 11),
            SizedBox(width: 6),
            SkeletonBox(width: 90, height: 22, radius: 11),
            SizedBox(width: 6),
            SkeletonBox(width: 60, height: 22, radius: 11),
          ]),
        ],
      ]),
    );
  }
}

/// Default loading state for lists: a few pulsing cards (+ optional caption,
/// e.g. while the AI is reading the competition).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.lines = 2, this.avatar = false, this.chips = false, this.caption});

  final int count;
  final int lines;
  final bool avatar;
  final bool chips;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (caption != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(caption!, style: Theme.of(context).textTheme.bodySmall),
        ),
      SkeletonPulse(
        child: Column(children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SkeletonCard(lines: lines, avatar: avatar, chips: chips),
            ),
        ]),
      ),
    ]);
  }
}

/// Detail page: tall header card followed by list cards.
class SkeletonDetail extends StatelessWidget {
  const SkeletonDetail({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: SkeletonPulse(
          child: Column(children: [
            SkeletonCard(lines: 5, chips: true),
            SizedBox(height: 12),
            SkeletonCard(lines: 1),
            SizedBox(height: 12),
            SkeletonCard(lines: 2, avatar: true),
          ]),
        ),
      );
}

/// 2x2 metric tiles (admin dashboard).
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) => SkeletonPulse(
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.25,
          children: [for (var i = 0; i < count; i++) const SkeletonCard(lines: 1)],
        ),
      );
}
