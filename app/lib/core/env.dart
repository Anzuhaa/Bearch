/// Build-time configuration.
///
/// Run with:  flutter run --dart-define-from-file=env.json
/// (copy env.example.json -> env.json; env.json is git-ignored).
///
/// Only the public client key belongs here (publishable key `sb_publishable_…`,
/// or the legacy anon key). The Gemini key and the service-role key stay
/// server-side in Supabase Edge Function secrets.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Without Supabase config the app runs in "preview mode": no auth, sample
  /// data, and a role switch in the drawer so the UI can be built and demoed.
  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Email domains accepted at sign-in (the database enforces this too).
  static const allowedEmailDomains = ['student.uph.edu', 'uph.edu'];
}
