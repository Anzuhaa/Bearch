import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

enum UserRole { student, admin }

class Profile {
  const Profile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.onboarded,
    this.majorName,
    this.reputation,
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final bool onboarded;
  final String? majorName;
  final double? reputation;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        email: j['email'] as String,
        fullName: (j['full_name'] as String?) ?? '',
        role: j['role'] == 'admin' ? UserRole.admin : UserRole.student,
        onboarded: (j['onboarded'] as bool?) ?? false,
        majorName: (j['majors'] as Map<String, dynamic>?)?['name'] as String?,
        reputation: (j['reputation'] as num?)?.toDouble(),
      );

  static const preview = Profile(
    id: 'preview',
    email: 'satria.jagad@student.uph.edu',
    fullName: 'Satria Jagad',
    role: UserRole.student,
    onboarded: true,
    majorName: 'Informatics',
    reputation: 4.8,
  );
}

/// Null in preview mode (no Supabase config).
final supabaseProvider = Provider<SupabaseClient?>(
  (ref) => Env.isConfigured ? Supabase.instance.client : null,
);

final authStateProvider = StreamProvider<AuthState?>((ref) {
  final client = ref.watch(supabaseProvider);
  if (client == null) return Stream.value(null);
  return client.auth.onAuthStateChange;
});

final profileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authStateProvider);
  final client = ref.watch(supabaseProvider);
  if (client == null) {
    final role = ref.watch(previewRoleProvider);
    return role == UserRole.admin
        ? const Profile(
            id: 'preview-admin',
            email: 'student.affairs@uph.edu',
            fullName: 'Student Affairs',
            role: UserRole.admin,
            onboarded: true,
          )
        : Profile.preview;
  }
  final uid = client.auth.currentUser?.id;
  if (uid == null) return null;
  final row = await client
      .from('profiles')
      .select('id, email, full_name, role, onboarded, reputation, majors(name)')
      .eq('id', uid)
      .maybeSingle();
  return row == null ? null : Profile.fromJson(row);
});

/// Preview-mode role switch (drawer toggle). Ignored when Supabase is configured.
class PreviewRoleNotifier extends Notifier<UserRole> {
  @override
  UserRole build() => UserRole.student;

  void toggle() => state = state == UserRole.student ? UserRole.admin : UserRole.student;
}

final previewRoleProvider = NotifierProvider<PreviewRoleNotifier, UserRole>(PreviewRoleNotifier.new);

final roleProvider = Provider<UserRole>(
  (ref) => ref.watch(profileProvider).value?.role ?? UserRole.student,
);
