import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/language_service.dart';
import 'auth_provider.dart';
import 'auth_state.dart';

/// Decides where an authenticated user belongs:
///   - not authenticated   → /login
///   - no language picked   → /language
///   - otherwise            → /home
Future<String> resolvePostAuthRoute(WidgetRef ref) async {
  final auth = ref.read(authProvider);
  if (auth is! AuthAuthenticated) return '/login';

  final lang = await ref.read(languageProvider.future);
  if (lang == null) return '/language';

  return '/home';
}
