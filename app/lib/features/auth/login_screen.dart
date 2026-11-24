import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

String friendlyAuthError(Object e) {
  final msg = e is AuthException ? e.message : e.toString();
  // The DB trigger rejects non-UPH emails; GoTrue surfaces that as a generic DB error.
  if (msg.contains('Database error saving new user') || msg.contains('Only verified UPH')) {
    return 'Only verified UPH accounts can join Bearch.';
  }
  return msg;
}

/// Figma 01 · Login (mobile): UPH email -> 6-digit code.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final email = (v ?? '').trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(email)) return 'Enter your UPH email';
    final domain = email.split('@').last;
    if (!Env.allowedEmailDomains.contains(domain)) return 'Use @student.uph.edu or @uph.edu';
    return null;
  }

  Future<void> _continue() async {
    if (!_form.currentState!.validate()) return;
    final client = ref.read(supabaseProvider);
    final email = _email.text.trim().toLowerCase();
    if (client == null) {
      context.go('/browse');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await client.auth.signInWithOtp(email: email, shouldCreateUser: true);
      if (mounted) context.push('/verify?email=${Uri.encodeQueryComponent(email)}');
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demoLogin(String email) async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await client.auth.signInWithPassword(email: email, password: Env.demoPassword);
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: BearchColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('B',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bearch', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text('Smarter Campus & Learning · UPH', style: t.labelSmall),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'Find the right teammates for every competition.',
                style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
              ),
              const SizedBox(height: 12),
              Text(
                'Cross-major matchmaking for UPH students: verified competitions, approval-based lobbies, '
                'shared team calendars and a reputation system that keeps every member accountable.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: 28),
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Welcome back 👋', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Sign in with your UPH email. Only verified UPH accounts can join Bearch.',
                          style: t.bodySmall),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _continue(),
                        validator: _validate,
                        decoration: const InputDecoration(
                          labelText: 'UPH email',
                          hintText: 'name@student.uph.edu',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: t.bodySmall?.copyWith(color: BearchColors.danger)),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _continue,
                        child: _busy
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Continue with UPH email'),
                      ),
                      const SizedBox(height: 12),
                      Tooltip(
                        message: 'Coming soon: needs an official UPH Mobile integration',
                        child: OutlinedButton(
                          onPressed: null,
                          child: const Text('Sign in with UPH Mobile'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Accepts @student.uph.edu and @uph.edu only',
                        textAlign: TextAlign.center,
                        style: t.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
              if (Env.demoLogin && Env.isConfigured) ...[
                const SizedBox(height: 16),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Pill('Demo', color: BearchColors.warning),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Hackathon demo accounts', style: t.titleSmall)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final a in Env.demoAccounts)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: InitialsAvatar(a.label, size: 32),
                          title: Text(a.label),
                          subtitle: Text(a.email),
                          trailing: const Icon(Icons.login_rounded, size: 18),
                          onTap: _busy ? null : () => _demoLogin(a.email),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma 02 · Verify UPH Email: 6-digit code + resend countdown.
class VerifyOtpScreen extends ConsumerStatefulWidget {
  const VerifyOtpScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends ConsumerState<VerifyOtpScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  int _resendIn = 45;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      if (mounted) setState(() => _resendIn--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final client = ref.read(supabaseProvider);
    if (client == null || _code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await client.auth.verifyOTP(email: widget.email, token: _code.text, type: OtpType.email);
      // Router redirect takes over once the session exists.
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return;
    try {
      await client.auth.signInWithOtp(email: widget.email, shouldCreateUser: true);
      _startTimer();
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mm = (_resendIn ~/ 60).toString();
    final ss = (_resendIn % 60).toString().padLeft(2, '0');
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Back')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.mark_email_read_outlined, size: 40, color: BearchColors.accent),
                  const SizedBox(height: 12),
                  Text('Check your UPH inbox',
                      textAlign: TextAlign.center, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('We sent a 6-digit code to ${widget.email}', textAlign: TextAlign.center, style: t.bodyMedium),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: t.headlineMedium?.copyWith(letterSpacing: 12, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(counterText: '', hintText: '••••••'),
                    onChanged: (v) {
                      if (v.length == 6) _verify();
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: BearchColors.danger)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: const Text('Verify & continue'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _resendIn > 0 ? null : _resend,
                    child: Text(_resendIn > 0 ? 'Didn\'t get it? Resend in $mm:$ss' : 'Resend code'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
