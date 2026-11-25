import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/theme.dart';
import 'core/theme_mode.dart';
import 'core/theme_reveal.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only (phones). Manifest/Info.plist set the same at launch.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (Env.isConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
  }
  await _preloadMontserrat();
  runApp(const ProviderScope(child: BearchApp()));
}

/// Load Montserrat before the first frame so widgets (e.g. chips) are not measured
/// with the fallback font and then clipped. Capped so offline start isn't blocked.
Future<void> _preloadMontserrat() async {
  for (final w in [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800]) {
    GoogleFonts.montserrat(fontWeight: w);
  }
  try {
    await GoogleFonts.pendingFonts().timeout(const Duration(milliseconds: 1500));
  } catch (_) {
    // Offline or slow network: start anyway with the fallback font.
  }
}

// Built once: rebuilding ThemeData (incl. the Montserrat text theme) on every
// theme toggle cost a frame.
final _lightTheme = buildBearchTheme(Brightness.light);
final _darkTheme = buildBearchTheme(Brightness.dark);

class BearchApp extends ConsumerWidget {
  const BearchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Bearch',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: ref.watch(themeModeProvider),
      // Theme changes are animated by ThemeReveal (one snapshot), not by lerping ThemeData.
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => ThemeReveal(child: child ?? const SizedBox.shrink()),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
