import 'package:supabase_flutter/supabase_flutter.dart';

String friendlyAuthError(Object e) {
  final msg = e is AuthException ? e.message : e.toString();
  // The DB trigger rejects non-UPH emails; GoTrue surfaces that as a generic DB error.
  if (msg.contains('Database error saving new user') || msg.contains('Only verified UPH')) {
    return 'Only verified UPH accounts can join Bearch.';
  }
  return msg;
}
