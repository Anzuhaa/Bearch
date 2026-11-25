
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/env.dart';
import '../core/glass.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/theme_mode.dart';
import '../features/notifications/notifications_sheet.dart';
import 'bearch_drawer.dart';
import 'nav_items.dart';

/// Mobile adaptation of the Figma sidebar: app bar + glass navigation drawer.
///
/// Android back: closes the drawer if open, otherwise returns to the home page
/// (drawer navigation uses `go`, so there is no back stack), and only exits
/// the app from home.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _drawerOpen = false;

  String get _home => ref.read(roleProvider) == UserRole.admin ? '/admin' : '/browse';

  @override
  Widget build(BuildContext context) {
    final item = navItemFor(widget.location);
    final atHome = widget.location == _home;
    return PopScope(
      canPop: atHome && !_drawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_drawerOpen) {
          _scaffoldKey.currentState?.closeDrawer();
        } else {
          context.go(_home);
        }
      },
      child: AppBackground(
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          onDrawerChanged: (open) => setState(() => _drawerOpen = open),
          appBar: AppBar(
            title: Text(item?.label ?? 'Bearch'),
            actions: [
              const ThemeToggleButton(),
              const NotificationBell(),
            ],
          ),
          drawer: BearchDrawer(location: widget.location),
          body: Column(
            children: [
              if (!Env.isConfigured) const _PreviewBanner(),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: BearchColors.warning.withValues(alpha: 0.15),
      child: Text(
        'Preview mode · Supabase not configured (sample data)',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
