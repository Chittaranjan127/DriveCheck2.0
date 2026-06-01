# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

DriveCheck is a Flutter app for Cars24 Car Jockeys (field car evaluators). It is a voice-and-vision AI copilot that guides a jockey through a 12-step inspection in Hindi, analyzes photos/audio via backend AI, and produces a price estimate. Users are low-tech Hindi speakers — voice is the primary interface, one action per screen, large buttons.

The product spec, full target architecture, and design tokens live in `FLUTTER_README.md` (32 KB). Treat it as the source of truth for *intended* shape; the actual `lib/` tree today is an early scaffold (auth flow + home placeholder only). When asked to build new features, cross-reference the spec for the directory layout, naming, and strings rather than inventing them.

## Commands

```bash
flutter pub get                  # install deps after touching pubspec.yaml
flutter run                      # run on attached device/simulator
flutter analyze                  # static analysis (flutter_lints rules)
flutter test                     # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter test --name "substring"      # run tests matching a name
flutter build apk                # release Android build
```

`.env` is loaded at startup via `flutter_dotenv` and is declared as a Flutter asset in `pubspec.yaml` — keep it in sync with `.env.example` when adding keys, and re-run `flutter pub get` if asset declarations change.

## Architecture

- **State:** `flutter_riverpod`. Providers live next to their feature (`features/<x>/<x>_provider.dart`). The auth slice uses an explicit sealed-class state machine (`AuthState` in `lib/features/auth/auth_state.dart`) — follow that pattern for new async flows rather than ad-hoc booleans.
- **Routing:** `go_router` defined in `lib/core/router/app_router.dart` as a single `Provider<GoRouter>`. Add new screens by registering a route here; pass data via `state.extra` (see `/otp`).
- **Entry:** `main.dart` loads dotenv then wraps `DriveCheckApp` in `ProviderScope`. `app.dart` is a `ConsumerWidget` that wires the router and `AppTheme.light` into `MaterialApp.router`.
- **Auth is real, backend-backed.** `AuthNotifier` hits `/auth/request-otp` and `/auth/verify-otp` on the SAM backend; the JWT returned by verify lives in `AuthTokenHolder` and gets attached as `Authorization: Bearer …` by the Dio interceptor. In dev the request-otp response also returns `mockOtp` so the OTP screen can pre-fill during demos. Firebase is NOT used — don't add `firebase_core` / `firebase_auth`. When changing auth, preserve the `AuthState` shape in `lib/features/auth/auth_state.dart` so screens don't need to change.
- **Localization is manual, not Flutter `intl`.** All user-visible strings go in `lib/core/constants/app_strings.dart`; never hardcode text in widgets. Default language is Hindi, written in romanized Hindi (e.g. `'Mobile number daalo'`). `LanguageNotifier` (SharedPreferences-backed) holds the current `AppLanguage` — supported values: `english`, `hindi`, `telugu`, `bengali`. A `null` value means the user hasn't picked yet → route to `/language`.
- **Theme:** Cars24 red `#E63946` primary. Tokens live in `lib/core/theme/{app_colors,app_text_styles,app_theme}.dart` — edit there only. Typography uses `google_fonts`: Poppins for Latin, `NotoSansDevanagari` for Hindi (use the `hindi*` text styles for Devanagari content).
- **Backend URLs:** centralised in `lib/core/constants/api_endpoints.dart`, read from `API_BASE_URL` in `.env`. Don't hardcode URLs in services.
- **HTTP:** `dio` is the chosen client (already in `pubspec.yaml`); no `ApiService` exists yet — when adding one, put it under `lib/core/services/`.

## Conventions

- Layout: `core/` (theme, constants, services, router), `features/<feature>/` (screens + providers + feature widgets), `shared/widgets/` (cross-feature widgets).
- Riverpod is plain `Notifier` / `AsyncNotifier` — no code-gen / `@riverpod` annotations are wired up. Don't introduce `riverpod_generator` without updating tooling.
- Romanized Hindi is intentional (jockeys are more comfortable reading it than Devanagari). Don't "fix" strings to Devanagari unless explicitly asked.
- Compression matters: per the spec, photos must be compressed on-device before upload, with per-step quality (documents 85, exterior 75). When implementing capture, read `kCompressionByStep` from the spec rather than picking a default.
