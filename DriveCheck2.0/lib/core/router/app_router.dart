import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/language/language_selection_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/shell/main_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/otp',
        builder: (_, state) => OtpScreen(phoneNumber: state.extra as String? ?? ''),
      ),
      GoRoute(path: '/language', builder: (_, _) => const LanguageSelectionScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/home', builder: (_, _) => const MainShell()),
    ],
  );
});
