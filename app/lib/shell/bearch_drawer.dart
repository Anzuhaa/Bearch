import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/env.dart';
import '../core/glass.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'nav_items.dart';

class BearchDrawer extends ConsumerWidget {
  const BearchDrawer({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final profile = ref.watch(profileProvider).value;
    final glass = GlassTokens.of(context);
    final t = Theme.of(context).textTheme;
    final sections = role == UserRole.admin ? adminNav : studentNav;

    return Drawer(
      width: 300,
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), // the one real blur on screen
          // Material (not a coloured Container) so ListTile ink/selection stays visible.
          child: Material(
            color: glass.fill,
            shape: Border(right: BorderSide(color: glass.border)),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3D9BFF), BearchColors.accent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Text('B',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Bearch',
                                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                  overflow: TextOverflow.ellipsis),
                              Text('UPH Teammate Finder', style: t.labelSmall, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final section in sections) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
                            child: Text(
                              section.title.toUpperCase(),
                              style: t.labelSmall?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w600),
                            ),
                          ),
                          for (final item in section.items)
                            _DrawerTile(
                              item: item,
                              selected: navItemFor(location)?.path == item.path,
                            ),
                        ],
                      ],
                    ),
                  ),
                  if (!Env.isConfigured)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      title: Text('Preview as admin', style: t.bodyMedium),
                      value: role == UserRole.admin,
                      onChanged: (_) {
                        ref.read(previewRoleProvider.notifier).toggle();
                        context.go(role == UserRole.admin ? '/browse' : '/admin');
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: GlassCard(
                      padding: const EdgeInsets.all(12),
                      // Students: tap to edit the skill profile.
                      onTap: role == UserRole.student && Env.isConfigured
                          ? () {
                              Navigator.of(context).pop();
                              context.push('/onboarding');
                            }
                          : null,
                      child: Row(
                        children: [
                          InitialsAvatar(profile?.fullName ?? '?', size: 36),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile?.fullName ?? '…',
                                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  [
                                    profile?.role == UserRole.admin ? 'Student Affairs' : profile?.majorName,
                                    if (profile?.reputation != null) '★ ${profile!.reputation!.toStringAsFixed(1)}',
                                  ].whereType<String>().join(' · '),
                                  style: t.labelSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sign out',
                            icon: const Icon(Icons.logout_rounded, size: 20),
                            onPressed: () => ref.read(supabaseProvider)?.auth.signOut(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({required this.item, required this.selected});

  final NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? BearchColors.accent : Theme.of(context).textTheme.bodyMedium?.color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: BearchColors.accent.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(item.icon, color: color, size: 22),
        title: Text(
          item.label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
        ),
        onTap: () {
          Navigator.of(context).pop();
          item.pushed ? context.push(item.path) : context.go(item.path);
        },
      ),
    );
  }
}
