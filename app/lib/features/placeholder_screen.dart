import 'package:flutter/material.dart';

import '../core/glass.dart';
import '../core/theme.dart';
import '../router.dart';

/// Stand-in for screens not built yet. Shows the Figma frames to follow and
/// the backend contract (RPCs / tables / functions) the screen should use.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.item});

  final NavItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final standalone = Scaffold.maybeOf(context) == null;

    Widget section(String title, List<String> lines, IconData icon) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 16, color: BearchColors.accent),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l, style: t.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        );

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item.icon, color: BearchColors.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item.label, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
                  const Pill('To build', color: BearchColors.warning),
                ],
              ),
              if (item.figma.isNotEmpty) section('Figma frames', item.figma, Icons.design_services_outlined),
              if (item.plan.isNotEmpty) section('Screen plan', item.plan, Icons.check_circle_outline_rounded),
              if (item.backend.isNotEmpty) section('Backend', item.backend, Icons.storage_rounded),
            ],
          ),
        ),
      ],
    );

    if (!standalone) return body;
    return AppBackground(
      child: Scaffold(backgroundColor: Colors.transparent, appBar: AppBar(title: Text(item.label)), body: body),
    );
  }
}
