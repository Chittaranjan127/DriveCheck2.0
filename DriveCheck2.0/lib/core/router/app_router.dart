import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/inspection_flow/inspection_flow_screen.dart';
import '../../features/inspection_report/inspection_report_screen.dart';
import '../../features/inspection_report/inspection_review_screen.dart';
import '../../features/language/language_selection_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/profile_setup_name_screen.dart';
import '../../features/profile/profile_setup_selfie_screen.dart';
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
      GoRoute(path: '/profile/setup/name', builder: (_, _) => const ProfileSetupNameScreen()),
      GoRoute(path: '/profile/setup/selfie', builder: (_, _) => const ProfileSetupSelfieScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/home', builder: (_, _) => const MainShell()),
      GoRoute(
        path: '/inspection/:id',
        builder: (_, state) => InspectionFlowScreen(inspectionId: state.pathParameters['id']!),
      ),
      // Pre-pricing review. The test-drive save handler routes here
      // first — the jockey scans every captured step before tapping
      // Confirm, which then forwards to the AI-pricing report.
      GoRoute(
        path: '/inspection/:id/review',
        builder: (_, state) =>
            InspectionReviewScreen(inspectionId: state.pathParameters['id']!),
      ),
      // Read-only view of a completed inspection — every step's data
      // + the deal outcome (accepted / counter-offer / declined +
      // final price). Reached by tapping a completed card on home.
      // No action buttons, AppBar close goes back to home.
      GoRoute(
        path: '/inspection/:id/view',
        builder: (_, state) => InspectionReviewScreen(
          inspectionId: state.pathParameters['id']!,
          readOnly: true,
        ),
      ),
      // Post-review AI-pricing report. Fetches the gpt-4o-generated
      // price + jockey pitch and lets the jockey raise a lead/ticket.
      GoRoute(
        path: '/inspection/:id/report',
        builder: (_, state) =>
            InspectionReportScreen(inspectionId: state.pathParameters['id']!),
      ),
    ],
  );
});
