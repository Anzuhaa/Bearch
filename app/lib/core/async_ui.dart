import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'glass.dart';
import 'skeleton.dart';
import 'theme.dart';
import 'theme_mode.dart';

/// Human-readable message for Supabase / network errors.
String errorText(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['error'] != null) return '${d['error']}';
    return e.reasonPhrase ?? 'Server function failed (${e.status})';
  }
  if (e is StorageException) return e.message;
  return e.toString().replaceFirst('Exception: ', '');
}

/// Loading / error (with retry) / data for an [AsyncValue].
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.loading});

  final AsyncValue<T> value;
  /// Skeleton shown while loading (default: a few pulsing cards).
  final Widget? loading;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading ?? const SkeletonList(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Something went wrong',
          message: errorText(e),
          action: onRetry == null ? null : OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ),
      data: data,
    );
  }
}

/// Shown on backend-only screens when the app runs in preview mode.
class NeedsBackend extends StatelessWidget {
  const NeedsBackend({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Needs the Bearch backend',
          message: 'Run with --dart-define-from-file=env.json to use this screen.',
        ),
      );
}

/// Runs a mutation with snackbar feedback. Returns true on success.
Future<bool> runAction(BuildContext context, Future<void> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) messenger.showSnackBar(SnackBar(content: Text(success)));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(backgroundColor: BearchColors.danger, content: Text(errorText(e))));
    return false;
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: BearchColors.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Single text input dialog. Returns null when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String confirmLabel = 'OK',
  int minLength = 0,
  int maxLines = 3,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: maxLines,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            helperText: minLength > 0 ? 'At least $minLength characters' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: controller.text.trim().length < minLength
                ? null
                : () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

/// Full-screen page outside the drawer shell (detail pages). Back arrow is automatic.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, required this.body, this.actions = const []});

  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(title), actions: [...actions, const ThemeToggleButton()]),
        body: body,
      ),
    );
  }
}

/// Section title used inside screens ("JOIN REQUESTS · 3").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.1, fontWeight: FontWeight.w700),
              ),
            ),
            ?trailing,
          ],
        ),
      );
}

final _dateFmt = DateFormat('d MMM yyyy');
String formatDate(DateTime d) => _dateFmt.format(d);

/// Teams auto-lock at 23:59 WIB the day before the registration deadline (H-1).
String lockTimeLabel(DateTime deadline) =>
    '${DateFormat('d MMM').format(deadline.subtract(const Duration(days: 1)))}, 23:59 WIB';

/// Whole days from today (local) to [deadline].
int daysUntil(DateTime deadline) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTime(deadline.year, deadline.month, deadline.day).difference(today).inDays;
}


/// Keep an autoDispose provider's data for [duration] after the last listener
/// leaves, so going back to a screen shows cached data instantly instead of a
/// spinner (the backend is ~350ms away). Mutations still invalidate it.
extension CacheFor on Ref {
  void cacheFor(Duration duration) {
    final link = keepAlive();
    final timer = Timer(duration, link.close);
    onDispose(timer.cancel);
  }
}
