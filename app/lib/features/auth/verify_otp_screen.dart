import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/glass.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/theme_mode.dart';
import 'auth_errors.dart';

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
        appBar: AppBar(title: const Text('Back'), actions: const [ThemeToggleButton()]),
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
