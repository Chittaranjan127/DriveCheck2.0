import 'package:shared_preferences/shared_preferences.dart';

/// Holds the current JWT in memory so the Dio interceptor can read it
/// synchronously, and mirrors writes to SharedPreferences so the session
/// survives app restarts.
///
/// Bootstrap with `await AuthTokenHolder.instance.load()` before runApp.
class AuthTokenHolder {
  static const _kKey = 'auth_jwt';
  static final AuthTokenHolder instance = AuthTokenHolder._();
  AuthTokenHolder._();

  String? _token;
  String? get current => _token;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kKey);
  }

  Future<void> set(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, token);
  }

  Future<void> clear() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}
