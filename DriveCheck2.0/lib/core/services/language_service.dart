import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  english(code: 'en', nativeName: 'English',  englishName: 'English'),
  hindi  (code: 'hi', nativeName: 'हिंदी',     englishName: 'Hindi'),
  telugu (code: 'te', nativeName: 'తెలుగు',   englishName: 'Telugu'),
  bengali(code: 'bn', nativeName: 'বাংলা',     englishName: 'Bengali');

  final String code;
  final String nativeName;
  final String englishName;
  const AppLanguage({required this.code, required this.nativeName, required this.englishName});

  static AppLanguage fromCode(String? code) =>
      AppLanguage.values.firstWhere((l) => l.code == code, orElse: () => AppLanguage.hindi);
}

const _kLanguageKey = 'app_language';

/// Persists chosen language across app launches.
class LanguageNotifier extends AsyncNotifier<AppLanguage?> {
  @override
  Future<AppLanguage?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kLanguageKey);
    return stored == null ? null : AppLanguage.fromCode(stored);
  }

  Future<void> setLanguage(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguageKey, language.code);
    state = AsyncData(language);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLanguageKey);
    state = const AsyncData(null);
  }
}

final languageProvider = AsyncNotifierProvider<LanguageNotifier, AppLanguage?>(LanguageNotifier.new);
