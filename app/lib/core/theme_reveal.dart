import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Light/dark switch as a circular reveal from the toggle button.
///
/// Why: animating ThemeData (MaterialApp's default) rebuilds and re-lays out the
/// whole app on every frame of the transition, which dropped frames on device.
/// Instead we take ONE snapshot of the current screen, switch the theme
/// instantly underneath, and grow a hole in the snapshot. Per frame that is a
/// single clipped image draw.
class ThemeReveal extends StatefulWidget {
  const ThemeReveal({super.key, required this.child});

  final Widget child;

  static ThemeRevealState? of(BuildContext context) => context.findAncestorStateOfType<ThemeRevealState>();

  @override
  State<ThemeReveal> createState() => ThemeRevealState();
}

class ThemeRevealState extends State<ThemeReveal> with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic);
  ui.Image? _snapshot;
  Offset _center = Offset.zero;

  static final bool _inTests = Platform.environment.containsKey('FLUTTER_TEST');

  /// Runs [switchTheme] behind a reveal that starts at [center] (global coords).
  Future<void> reveal(Offset center, VoidCallback switchTheme) async {
    final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (_inTests || _snapshot != null || boundary == null) {
      switchTheme();
      return;
    }
    // Half resolution: 4x less GPU readback; the old screen is only visible while
    // the circle sweeps across it, so the softness is not noticeable.
    final image = await boundary.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context) / 2);
    if (!mounted) return image.dispose();
    setState(() {
      _snapshot = image;
      _center = center;
    });
    // Let the overlay paint first, then rebuild with the new theme on the next frame
    // so the snapshot and the theme rebuild don't land in the same frame.
    await WidgetsBinding.instance.endOfFrame;
    switchTheme();
    await _c.forward(from: 0);
    if (!mounted) return image.dispose();
    setState(() => _snapshot = null);
    image.dispose();
  }

  @override
  void dispose() {
    _c.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (snapshot != null)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(builder: (context, box) {
                final size = box.biggest;
                final maxRadius = [
                  Offset.zero,
                  Offset(size.width, 0),
                  Offset(0, size.height),
                  Offset(size.width, size.height),
                ].map((corner) => (corner - _center).distance).reduce(math.max);
                return AnimatedBuilder(
                  animation: _t,
                  builder: (context, child) => ClipPath(
                    clipper: _HoleClipper(_center, maxRadius * _t.value),
                    child: child,
                  ),
                  child: RawImage(image: snapshot, width: size.width, height: size.height, fit: BoxFit.fill),
                );
              }),
            ),
          ),
      ],
    );
  }
}

/// Everything except a growing circle: the old theme stays outside the circle.
class _HoleClipper extends CustomClipper<Path> {
  _HoleClipper(this.center, this.radius);

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_HoleClipper old) => old.radius != radius || old.center != center;
}
