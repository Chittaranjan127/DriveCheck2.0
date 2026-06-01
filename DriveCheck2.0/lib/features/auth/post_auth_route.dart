import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/user.dart';
import '../../core/services/language_service.dart';
import 'auth_provider.dart';
import 'auth_state.dart';

/// Decides where an authenticated user belongs:
///   - no language picked  → /language
///   - no name             → /profile/setup/name
///   - no selfie url       → /profile/setup/selfie
///   - otherwise           → /home
///
/// All three onboarding gates write back to the User row, so [refreshMe] is
/// the natural follow-up after the user completes each step.
Future<String> resolvePostAuthRoute(WidgetRef ref) async {
  final auth = ref.read(authProvider);
  if (auth is! AuthAuthenticated) return '/login';

  final lang = await ref.read(languageProvider.future);
  if (lang == null) return '/language';

  return _routeForUser(auth.user);
}

String _routeForUser(User u) {
  if ((u.name?.trim().isEmpty ?? true)) return '/profile/setup/name';
  if ((u.selfieUrl?.isEmpty ?? true)) return '/profile/setup/selfie';
  return '/home';
}

/// Synchronous variant for callers that already have the language resolved.
String routeForUserSync({required User user, required dynamic language}) {
  if (language == null) return '/language';
  return _routeForUser(user);
}
