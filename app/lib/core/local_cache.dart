import 'package:shared_preferences/shared_preferences.dart';

/// Tiny on-device cache so a cold start can show the right screen and the last
/// known data on the first frame, then refresh from the network (~350ms away).
/// Only non-sensitive data: a user's role and the public competitions list.
abstract final class LocalCache {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null; // cache is an optimisation only
    }
  }

  static String? roleFor(String uid) => _prefs?.getString('role:$uid');
  static Future<void> setRole(String uid, String role) async => _prefs?.setString('role:$uid', role);

  static String? get competitionsJson => _prefs?.getString('competitions');
  static Future<void> setCompetitionsJson(String json) async => _prefs?.setString('competitions', json);
}
