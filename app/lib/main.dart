import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/theme.dart';
import 'core/theme_mode.dart';
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
    await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Offline or slow network: start anyway with the fallback font.
  }
}

class BearchApp extends ConsumerWidget {
  const BearchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Bearch',
      debugShowCheckedModeBanner: false,
      theme: buildBearchTheme(Brightness.light),
      darkTheme: buildBearchTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 300),
      themeAnimationCurve: Curves.easeInOut,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
