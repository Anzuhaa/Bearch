import 'package:bearch/main.dart';
import 'package:bearch/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// Tests run without --dart-define, so the app is in preview mode (no Supabase).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Phone-sized surface (390x844 @3x) instead of the default 800x600.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1170, 2532);
    view.devicePixelRatio = 3;
  });
  tearDown(() => TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset());

  testWidgets('preview mode boots into Browse with sample competitions', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BearchApp()));
    await tester.pumpAndSettle();

    expect(find.text('Browse Competitions'), findsOneWidget);
    expect(find.textContaining('Preview mode'), findsOneWidget);
    expect(find.text('UPH STACK Hackathon 2026'), findsOneWidget);
  });

  testWidgets('drawer shows student sections, admin toggle swaps to admin nav', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BearchApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('MY TEAM', skipOffstage: false), findsOneWidget);
    expect(find.text('Rate & Claim SEP', skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('Preview as admin'));
    await tester.pumpAndSettle();

    // Navigated to the admin dashboard placeholder.
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('rpc admin_dashboard_stats'), findsOneWidget);
  });

  test('navItemFor resolves nested paths', () {
    expect(navItemFor('/admin/reports')?.label, 'Reports & Appeals');
    expect(navItemFor('/admin')?.label, 'Dashboard');
    expect(navItemFor('/team/chat')?.label, 'Team Chat');
    expect(navItemFor('/browse/abc')?.label, 'Browse Competitions');
  });

  testWidgets('dark theme builds', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const ProviderScope(child: BearchApp()));
    await tester.pumpAndSettle();
    expect(find.text('Browse Competitions'), findsOneWidget);
    expect(Theme.of(tester.element(find.text('Browse Competitions'))).brightness, Brightness.dark);
  });
}
