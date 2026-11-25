import 'dart:ui';

import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

/// Frosted-glass card used everywhere in Bearch.
///
/// Performance: a real backdrop blur re-samples everything behind the card on
/// every frame. One per screen is fine; one per list card makes scrolling janky.
/// Cards are 85% opaque over a soft static background, so by default they use
/// the translucent fill only. Pass `blur: true` for a lone hero card.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.onTap,
    this.blur = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTokens.of(context);
    final shape = BorderRadius.circular(radius);
    Widget card = Material(
      color: glass.fill,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: shape, side: BorderSide(color: glass.border)),
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    if (blur) {
      card = ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur), child: card),
      );
    }
    return PressScale(
      enabled: onTap != null,
      child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [BoxShadow(color: glass.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: card,
    ));
  }
}

/// Soft gradient blobs behind the glass, like the Figma frames.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = GlassTokens.of(context);
    final bg = Theme.of(context).scaffoldBackgroundColor;
    Widget blob(Color c, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
          ),
        );
    return ColoredBox(
      color: bg,
      child: Stack(
        children: [
          // Static blobs live in their own layer (painted once, not on every scroll frame).
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(clipBehavior: Clip.hardEdge, children: [
                Positioned(top: -120, left: -100, child: blob(glass.blobs[0], 380)),
                Positioned(top: -60, right: -120, child: blob(glass.blobs[1], 340)),
                Positioned(bottom: -140, left: 40, child: blob(glass.blobs[2], 420)),
              ]),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// Small rounded status label ("Verified", "Campus", "94% match").
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color = BearchColors.accent, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Circle with initials ("SJ"), coloured deterministically from the name.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 40});

  final String name;
  final double size;

  static const _palette = [
    BearchColors.accent,
    Color(0xFFFF9F0A),
    Color(0xFF30B0C7),
    BearchColors.purple,
    BearchColors.success,
    Color(0xFFFF375F),
  ];

  @override
  Widget build(BuildContext context) {
    // Only words that start with a letter: "Satria (Demo)" -> "S", not "S(".
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => RegExp(r'^\p{L}', unicode: true).hasMatch(p)).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
    final color = _palette[name.hashCode.abs() % _palette.length];
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.36),
      ),
    );
  }
}

/// Centered empty / fallback state with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: BearchColors.accent),
          const SizedBox(height: 12),
          Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: t.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
