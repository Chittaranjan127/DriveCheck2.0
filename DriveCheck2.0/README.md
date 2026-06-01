# DriveCheck

**Cars24 AI Inspection Copilot · Token '26 Hackathon · Problem Statement 3**

A voice-and-vision AI copilot for Cars24 Car Jockeys. The app guides a
field evaluator through a 13-step car inspection in Hindi, analyses every
photo and audio capture using AI, and writes a ready-to-read negotiation
pitch the jockey reads to the seller on the doorstep.

> A first-day jockey with zero prior experience can complete the same
> inspection as a five-year veteran.

---

## What's in this repo

This is the **app repo**. The product spans three repos:

| Repo | Stack | What it does |
| --- | --- | --- |
| **`DriveCheck/`** *(this one)* | Flutter 3.x · Dart · Riverpod · go_router | iOS + Android app the jockey uses on the doorstep. |
| **`drivecheck-backend/`** | AWS SAM · Node.js 20 (Lambda, arm64) · DynamoDB · AppSync | 18 Lambdas behind one API Gateway. Auth, inspections, AI proxies, real-time fan-out. |
| **`drivecheck-admin-ui/`** | Angular 20 · Material 20 · signals | Web dashboard the dispatcher uses to assign work and watch progress live. |

The companion repos sit next to this one inside the hackathon workspace.

---

## TL;DR for new teammates

```bash
flutter pub get        # install deps
cp .env.example .env   # fill in API_BASE_URL + APPSYNC_* (see below)
flutter run            # on a real device — uses camera, mic, location
```

The first run needs `.env` populated with the deployed AWS endpoints
(api gateway URL + api key, AppSync URL + key). Ask the team lead for
the current dev values, or grab them from CloudFormation stack outputs
in `drivecheck-backend/` (`npm run logs:inspections` will print the
stack name).

---

## Architecture in one picture

```
┌─────────────────┐                          ┌────────────────────────┐
│ Flutter app     │  ── REST (JWT + key) ──▶ │ API Gateway → Lambda × │
│  (jockey)       │                          │  18 Node.js handlers   │
│                 │  ◀── live (WebSocket) ── │  + Lambda layer        │
└────────┬────────┘                          └─────────┬──────────────┘
         │                                             │
         │                                             ▼
         │                                  ┌─────────────────────┐
         │                                  │  DynamoDB × 6 tables│
         │                                  │  Streams → publisher│
         │                                  └──────────┬──────────┘
         │                                             │
         │                                             ▼
         │                                  ┌─────────────────────┐
         │ ◀──── subscriptions ─── AppSync ─│  Realtime fan-out   │
         │                                  └─────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────┐
│ External AI                                                        │
│  OpenAI GPT-4o   ←  vision OCR, photo-quality, answer parsing,     │
│                     pricing report, jockey pitch                   │
│  OpenAI Whisper  ←  voice answer transcription (Hindi-aware)       │
│  OpenAI gpt-audio←  engine-sound classification                    │
│  ElevenLabs TTS  ←  Hindi voice instructions & negotiation script  │
└────────────────────────────────────────────────────────────────────┘
```

**Full HLD/LLD** lives in [`submission/`](submission/):

- [`submission/PITCH_DECK.md`](submission/PITCH_DECK.md) — slide-by-slide pitch + demo script.
- [`submission/HLD.md`](submission/HLD.md) — system context, components, data flow, AWS topology.
- [`submission/LLD.md`](submission/LLD.md) — Lambda inventory, schemas, REST + AppSync contracts, AI prompt designs, voice pipeline, gotchas.

---

## The 13 inspection steps

| # | Step | What the jockey does | What the AI does |
| --- | --- | --- | --- |
| 1 | Arrival | Taps "I'm here" | Reads location aloud, opens Maps |
| 2 | RC document | Snaps the registration card | OCR fills owner / year / fuel / RC#; flags booking mismatches |
| 3 | Instrument cluster | Snaps the dashboard | OCR fills odometer + decodes warning lights |
| 4–11 | Exterior + interior photos | Snaps each of 8 angles | Photo quality + subject-match verifier; rejects bad shots |
| 12 | Engine sound | 15 s mic recording, hood open | Audio classifier returns verdict + issue list |
| 13 | Test drive | Drives the car, hands-free Q&A | Asks 7 Hindi questions over the speaker, listens (VAD auto-stop on silence), classifies answers |
| End | Report + pitch | Reads the AI script to the seller | Estimates price, writes negotiation pitch, lists repairable issues that would bridge to the seller's quoted price |

Zero typing. Voice instructions in Hindi throughout. Drive-time UI is
fully hands-free.

---

## Languages

| Surface | Languages |
| --- | --- |
| UI labels + buttons | English, Hindi (romanized), Telugu, Bengali |
| AI bar voice + bubble text | English, Hindi (Devanagari), Telugu, Bengali |
| Spoken language for ElevenLabs | matches user's selected language |
| Backend AI prompts (report / pitch / next steps) | localised by `lang=` query param |

Translation strings live in
[`lib/core/i18n/translations.dart`](lib/core/i18n/translations.dart) —
one `Translations` class, one map per language, no codegen.

---

## Running locally

### Prereqs

```bash
flutter --version          # 3.x, Dart 3.12+
brew install fvm           # optional but recommended for version pinning
```

iOS requires Xcode 15+ and a real device (mic + camera). Android works
on emulator for everything except the AppSync live updates demo (use a
real phone for that).

### First run

```bash
flutter pub get
cp .env.example .env
# Edit .env — fill API_BASE_URL, API_KEY, APPSYNC_HTTPS_URL, APPSYNC_API_KEY
flutter run               # or: flutter run -d <deviceId>
```

### Useful commands

```bash
flutter analyze           # static analysis (flutter_lints rules)
flutter test              # all tests
flutter build apk         # release Android build
flutter build ipa         # release iOS build (needs signing)
```

### Demo account

The dev backend's `POST /auth/request-otp` returns a `mockOtp` in its
response — the OTP screen reads it and pre-fills so a tester can sign
in without an SMS gateway. Use any 10-digit phone number that already
exists in the `DriveCheck-Users-dev` table; the team has a couple of
seeded ones (ask in the team chat).

---

## Repo layout

```
lib/
├── core/
│   ├── constants/         api endpoints, inspection step defs, app strings
│   ├── i18n/              all visible strings (4 languages, no codegen)
│   ├── models/            Inspection, InspectionStepRow, InspectionReport, …
│   ├── router/            single Provider<GoRouter>
│   ├── services/          api / auth / tts / appsync / language / location
│   └── theme/             colors, text styles, MaterialApp theme
├── features/
│   ├── auth/              splash, login, OTP, post-auth gate
│   ├── home/              today's inspections + AI bottom bar
│   ├── inspection_flow/   the 13-step shell + per-step screens
│   │   ├── ai/            per-step OpenAI client wrappers
│   │   ├── prompts/       step intro Hindi/English/Telugu/Bengali pairs
│   │   ├── state/         assistant utterance + step rows providers
│   │   └── steps/         arrival, rc_document, …, engine_sound, test_drive
│   ├── inspection_report/ AI pricing + jockey pitch + bridge-to-ask
│   ├── inspections/       list / detail
│   ├── profile/           selfie + name + lang switch + AI-assistant toggle
│   └── shell/             bottom-nav (Home · Inspections · Profile)
└── shared/widgets/        cross-feature widgets
```

---

## Conventions worth knowing

- **State** — Riverpod plain `Notifier` / `AsyncNotifier` (no codegen). Auth uses a sealed `AuthState` state machine; follow that pattern for new async flows.
- **Routing** — `go_router` in one provider. New screen = one `GoRoute` registration.
- **Localisation** — every visible string flows through `Translations`. Romanized Hindi in UI buttons (jockey research showed they read it faster), Devanagari in the AI bar (system reads it aloud).
- **Theme** — Cars24 indigo primary, dark CTA system. Tokens live in `lib/core/theme/*` — edit there only.
- **HTTP** — Dio with x-api-key + Bearer JWT interceptors. Backend URLs in `.env`, exposed via `lib/core/constants/api_endpoints.dart`.
- **Image compression** — per-step quality factors in `kCompressionByStep`. RC + cluster: q=85 (OCR detail), exterior: q=75 (composition matters more than detail).
- **Voice** — `TtsService` is a singleton; all AI prompts go through `assistantUtteranceProvider.say()`. When the user disables the AI assistant in their profile, `say()` short-circuits and the bottom bar collapses.
- **Real-time** — `lib/core/services/appsync_subscription.dart` is a hand-rolled ~210-line WebSocket client (we didn't want to drag in Amplify for one subscription). Diagnostic logs print every connect/ack/subscribe/event so realtime issues are debuggable from the Flutter console.

---

## What's intentionally not in scope

- **Offline mode** — the per-step Riverpod + REST shape supports it; not implemented for the hackathon demo.
- **Push notifications** — `fcmToken` is captured at OTP verify, but we don't push yet. Reserved for dispatcher→jockey "new inspection" pings when the app is backgrounded.
- **S3 upload of photos** — today photos travel as base64 inside the Lambda payload (≤500 KB compressed, fits comfortably). Next step is presigned PUT URLs so images never traverse the backend.
- **Admin auth** — admin UI shares the app's API key today. Production answer is Cognito + a custom Lambda authorizer (Firebase is NOT on the roadmap).

---

## Where to go for more

| Want to know… | Read |
| --- | --- |
| Pitch / demo storyboard | [`submission/PITCH_DECK.md`](submission/PITCH_DECK.md) |
| Architecture, AWS topology, data flow | [`submission/HLD.md`](submission/HLD.md) |
| APIs, schemas, prompts, gotchas | [`submission/LLD.md`](submission/LLD.md) |
| Original product spec (32 KB) | [`FLUTTER_README.md`](FLUTTER_README.md) |
| Day-to-day code orientation | [`CLAUDE.md`](CLAUDE.md) |
| Backend deploy + endpoints | `drivecheck-backend/README.md` |

---

## Team

> Fill with team names + roles.

| Member | Role | Contact |
| --- | --- | --- |
| Chittaranjan Das | … | … |
| … | … | … |

Built for **Token '26 · Problem Statement 3** · 2026.
