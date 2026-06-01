# DriveCheck — Low Level Design (LLD)

> Implementation-level companion to `HLD.md`. APIs, schemas, prompts, the non-obvious bits.

This document is a **reference, not a tutorial**. Things that are well-explained in code comments aren't repeated here — pointers to file paths are given instead.

---

## 0 · Index

1. [Repos + layout](#1--repos--layout)
2. [Backend: Lambda inventory](#2--backend-lambda-inventory)
3. [DynamoDB schemas](#3--dynamodb-schemas)
4. [REST API contracts](#4--rest-api-contracts)
5. [AppSync schema + realtime flow](#5--appsync-schema--realtime-flow)
6. [AI prompt designs](#6--ai-prompt-designs)
7. [Flutter — state, routing, services](#7--flutter--state-routing-services)
8. [Voice pipeline (TTS + STT)](#8--voice-pipeline-tts--stt)
9. [Test-drive conversation flow](#9--test-drive-conversation-flow)
10. [Image compression strategy](#10--image-compression-strategy)
11. [Admin UI](#11--admin-ui)
12. [Non-obvious gotchas worth knowing](#12--non-obvious-gotchas-worth-knowing)

---

## 1 · Repos + layout

| Repo | Stack | Purpose |
| --- | --- | --- |
| `DriveCheck/` | Flutter 3.x, Dart 3.12 | Jockey app (iOS + Android). |
| `drivecheck-backend/` | AWS SAM, Node.js 20, arm64 | Single-stack serverless backend. |
| `drivecheck-admin-ui/` | Angular 20 standalone + Material 20 | Dispatcher web UI. |

App-side directory shape:

```
DriveCheck/lib/
├── core/                        cross-cutting infra
│   ├── constants/               (api_endpoints, app_strings, test_credentials, inspection_steps)
│   ├── i18n/translations.dart   single Translations class, 4 lang maps
│   ├── models/                  Inspection, InspectionReport, InspectionStepRow, …
│   ├── router/app_router.dart   go_router, single Provider<GoRouter>
│   ├── services/                api/auth/tts/uploads/language/appsync_subscription
│   └── theme/                   colors, text styles, theme
├── features/
│   ├── auth/                    splash, login, OTP, post-auth gate
│   ├── home/                    home screen, inspection cards, AppSync wiring
│   ├── inspection_flow/         the 13-step shell + per-step screens
│   │   ├── inspection_flow_screen.dart
│   │   ├── prompts/             step intro Hindi/English/Telugu/Bengali pairs
│   │   ├── ai/                  per-step OpenAI client wrappers
│   │   ├── state/               assistant_utterance_provider + step_rows_provider
│   │   ├── steps/               arrival, rc_document, instrument_cluster, …, test_drive
│   │   └── widgets/             AssistantBottomBar, StepExampleDialog
│   ├── inspection_report/       AI report screen + provider
│   ├── inspections/             list / details
│   ├── profile/                 selfie + profile-setup screens
│   ├── settings/                language, account
│   └── language/                first-time language pick
└── shared/widgets/              cross-feature widgets (cars24_wordmark, primary_button, app_bottom_nav)
```

Backend layout mirrors the route map:

```
drivecheck-backend/
├── template.yaml                CloudFormation (~1k lines, single stack)
├── auth/                        requestOtp, verifyOtp, getMe, updateMe, logout
├── ai/                          analyzeImage, analyzeAnswer, analyzeEngineSound, transcribe, tts
├── inspections/                 listInspections, getInspection, createInspection, getSteps,
│                                updateStep, uploadStepMedia, getReport, createTicket, createLead
├── users/                       listJockeys
├── uploads/                     signUploadUrl  (reserved for the S3 migration)
├── realtime/                    publishInspection (DDB Stream → AppSync mutation)
└── shared/utilities/nodejs/lib/ deployed as a Lambda layer
```

---

## 2 · Backend: Lambda inventory

All Node.js 20, arm64, single shared layer. Memory + timeout per function in `template.yaml`.

| Function | Route | Method | Auth | Purpose |
| --- | --- | --- | --- | --- |
| `requestOtp` | `/auth/request-otp` | POST | API key | Generates a 6-digit OTP into `UserOTPManager`, TTL 5 min. Dev returns it in `mockOtp`. |
| `verifyOtp` | `/auth/verify-otp` | POST | API key | Burns the OTP row, upserts user, creates `UserSessions` row, returns `{ token, user, sessionId }`. JWT 30 d, `jti = sessionId`. |
| `getMe` | `/auth/me` | GET | + JWT | Returns current user. |
| `updateMe` | `/auth/me` | PATCH | + JWT | Updates `name`, `email`, `preferredLanguage`, `employeeId`, `selfieUrl`. |
| `logout` | `/auth/logout` | POST | + JWT | Sets `revokedAt = now` on the session row. |
| `listJockeys` | `/jockeys` | GET | API key | Scans `Users` for `role=jockey`; admin's assignment dropdown. |
| `listInspections` | `/inspections?assignedTo&from&to` | GET | API key | Inspections by assignee + date range, or scan all. |
| `getInspection` | `/inspections/{id}` | GET | API key | Single inspection. |
| `createInspection` | `/inspections` | POST | API key | Writes parent row + 13 step rows transactionally. Accepts `quotedPriceInr` as the seller's anchor. |
| `getSteps` | `/inspections/{id}/steps` | GET | API key | All 13 step rows for an inspection. |
| `updateStep` | `/inspections/{id}/steps/{stepId}` | PATCH | API key | Append step result + media URLs + status. Accepts a `parentUpdates` whitelist to backfill `model`/`yearOfMake`/`fuelType` on the parent. |
| `uploadStepMedia` | `/inspections/{id}/steps/{stepId}/media` | POST | API key | Body: `{ mediaBase64, mimeType }`. Accepts both images (jpg/png/webp) and audio (wav/mp3/m4a/aac). Returns URL. |
| `getReport` | `/inspections/{id}/report?lang=hi` | GET | API key | Full AI report: pricing, jockey pitch, bridge-to-ask, next steps. Soft-fails AI sub-bundle. |
| `createTicket` | `/inspections/{id}/tickets` | POST | API key | Customer countered / declined. Outcome enum: `accepted`, `countered`, `declined`. |
| `createLead` | `/inspections/{id}/leads` | POST | API key | Customer accepted. Frozen snapshot of inspection + agreed price. |
| `analyzeImage` | `/ai/analyze-image` | POST | API key | GPT-4o vision proxy. Body: `{ prompt, imageBase64\|imageUrl, model? }`. Returns parsed JSON. |
| `analyzeAnswer` | `/ai/analyze-answer` | POST | API key | gpt-4o text classifier for test-drive answers. Returns `{ value, confidence, notes, acknowledgment }`. |
| `analyzeEngineSound` | `/ai/analyze-engine-sound` | POST | API key | `gpt-audio-1.5` (originally `gpt-4o-audio-preview`, swapped due to access). Returns `{ verdict, healthScore, detectedIssues[], summary }`. |
| `transcribe` | `/ai/transcribe` | POST | API key | Whisper proxy with `language` hint. |
| `tts` | `/ai/tts` | POST | API key | ElevenLabs proxy. Returns audio bytes; cache-friendly. |
| `publishInspection` | (DDB Stream event source) | — | IAM | Subscribed to the `Inspections` table stream; SigV4-signs an AppSync mutation per NEW_IMAGE. |

Two-layer auth model: every Lambda is behind the **API key**. Auth/profile Lambdas also call `requireAuth(event)` from the layer to verify the **JWT** and pull `claims.sub` (phone number).

---

## 3 · DynamoDB schemas

All tables on-demand, single region, server-side encryption with AWS-managed keys. Names suffixed by stage: `DriveCheck-Users-dev`, etc.

### `Users`
- **PK** `phoneNumber` (string)
- Attributes: `name`, `email`, `preferredLanguage`, `role` (`jockey` / `admin`), `status`, `employeeId`, `selfieUrl`, `createdAt`, `updatedAt`, `lastLoginAt`.

### `UserOTPManager`
- **PK** `phoneNumber`
- TTL on `ttl` attribute (5 min)
- Attributes: `otp`, `issuedAt`, `attemptsLeft`.

### `UserSessions`
- **PK** `sessionId` (UUID)
- **GSI** `byPhoneNumber (phoneNumber, lastSeenAt)`
- TTL on `ttl` (30 d)
- Attributes: `phoneNumber`, `fcmToken`, `deviceInfo {platform, model, appVersion}`, `ipAddress`, `userAgent`, `revokedAt`.

### `Inspections`
- **PK** `id` (UUID)
- **GSI** `byAssignee (assignedTo, scheduledAt)`
- **Stream** `NEW_IMAGE` → `PublishInspection` Lambda
- Attributes: `assignedTo`, `scheduledAt`, `carTitle`, `model`, `yearOfMake`, `fuelType`, `kmDriven`, `quotedPriceInr`, `customerName`, `customerPhone`, `area`, `address`, `latitude`, `longitude`, `status` (`scheduled`/`inProgress`/`completed`), `stepCount`, `completedStepCount`, `createdAt`, `updatedAt`.

### `InspectionSteps`
- **PK** `inspectionId` (string)
- **SK** `stepId` (string, e.g. `rc_document`)
- Attributes: `stepOrder`, `stepType`, `section`, `photoCount`, `audioSeconds`, `status` (`pending`/`inProgress`/`completed`), `mediaUrls[]`, `data` (free-form structured step result), `aiAnalysis` (structured AI output), `notes`, `createdAt`, `updatedAt`.
- One row per step, written transactionally with the parent on `createInspection`.

### `InspectionTickets`
- **PK** `id` (UUID)
- Attributes: `inspectionId`, `outcome` (`accepted`/`countered`/`declined`), `aiPriceInr`, `customerPriceInr` (nullable), `notes`, `createdAt`.

### `InspectionLeads`
- **PK** `id` (UUID)
- Attributes: `inspectionId`, `agreedPriceInr`, `aiPriceInr`, `inspectionSnapshot` (frozen JSON for procurement), `notes`, `createdAt`.

---

## 4 · REST API contracts

Every response wraps `{ ok, data, error? }`. Error payloads carry `{ code, message }`.

### Auth

```http
POST /auth/request-otp
{ "phoneNumber": "7606983009" }
→ 200 { "ok": true, "data": { "issued": true, "mockOtp": "123456" } }

POST /auth/verify-otp
{ "phoneNumber": "7606983009", "otp": "123456",
  "deviceInfo": { "platform": "ios", "appVersion": "1.0.0" } }
→ 200 { "ok": true, "data": { "token": "...", "user": {...}, "sessionId": "..." } }

GET /auth/me           Authorization: Bearer <jwt>
PATCH /auth/me         body: { name?, email?, preferredLanguage?, employeeId?, selfieUrl? }
POST /auth/logout
```

### Inspections

```http
GET /inspections?assignedTo=7606983009&from=ISO&to=ISO
GET /inspections/{id}
POST /inspections
{ "assignedTo": "7606983009", "scheduledAt": "2026-05-28T10:30:00Z",
  "carTitle": "Maruti Vitara Brezza", "model": "Vitara Brezza",
  "yearOfMake": 2019, "fuelType": "Petrol", "kmDriven": 47000,
  "quotedPriceInr": 720000, "area": "Indiranagar",
  "customerName": "Rohit Kumar", "customerPhone": "9876543210",
  "address": "...", "latitude": 12.9, "longitude": 77.6 }

GET /inspections/{id}/steps
PATCH /inspections/{id}/steps/{stepId}
{ "status": "completed", "mediaUrls": [...], "data": {...}, "aiAnalysis": {...},
  "parentUpdates": { "yearOfMake": 2019, "fuelType": "Petrol" } }

POST /inspections/{id}/steps/{stepId}/media
{ "mediaBase64": "...", "mimeType": "image/jpeg" }
→ 200 { "url": "https://..." }

GET /inspections/{id}/report?lang=hi
POST /inspections/{id}/tickets
{ "outcome": "countered", "aiPriceInr": 660000, "customerPriceInr": 700000, "notes": "..." }
POST /inspections/{id}/leads
{ "agreedPriceInr": 660000, "aiPriceInr": 660000, "notes": "..." }
```

### AI

```http
POST /ai/analyze-image
{ "prompt": "...", "imageBase64": "...", "model": "gpt-4o" }
→ 200 { "ok": true, "data": <model JSON, schema set by the prompt> }

POST /ai/analyze-answer
{ "transcription": "smooth chalti hai",
  "questionText": "Acceleration kaisi hai?",
  "expectedValues": ["smooth", "jerky", "slow", "unclear"],
  "language": "hi" }
→ 200 { "ok": true, "data": {
  "value": "smooth", "confidence": 0.92, "notes": null,
  "acknowledgment": "Theek hai, acceleration smooth." } }

POST /ai/analyze-engine-sound
{ "audioBase64": "...", "mimeType": "audio/wav", "language": "hi" }
→ 200 { "ok": true, "data": {
  "verdict": "minor_issue", "healthScore": 76,
  "detectedIssues": [{ "issue": "...", "severity": "minor" }],
  "summary": "..." } }

POST /ai/transcribe
{ "audioBase64": "...", "language": "hi" }
→ 200 { "ok": true, "data": { "text": "..." } }

POST /ai/tts
{ "ssml": "<speak>...</speak>", "voiceId": "HH8sIQq8WOcER3Nu118i", "speed": 0.85 }
→ audio/mpeg bytes
```

---

## 5 · AppSync schema + realtime flow

GraphQL schema (single mutation, single subscription):

```graphql
type Inspection {
  id: ID!
  assignedTo: String!
  status: String!
  completedStepCount: Int
  stepCount: Int
  carTitle: String
  customerName: String
  scheduledAt: String
  updatedAt: String
}

type Mutation {
  publishInspectionChanged(input: InspectionInput!): Inspection
    @aws_iam
}

input InspectionInput { … same fields as Inspection … }

type Subscription {
  onInspectionsForJockey(assignedTo: String!): Inspection
    @aws_subscribe(mutations: ["publishInspectionChanged"])
    @aws_api_key
}
```

Flow per change:
1. `createInspection` / `updateStep` / `updateInspection` writes to DDB.
2. `Inspections` table Stream emits a NEW_IMAGE record.
3. `PublishInspection` Lambda batches up to 25 records, calls `publishInspectionChanged(input)` per row.
4. AppSync compares the published `input.assignedTo` against each open subscription's `assignedTo` arg; matches fan out over WSS.

Flutter client lives in [`lib/core/services/appsync_subscription.dart`](../lib/core/services/appsync_subscription.dart) (~210 lines, single file, hand-rolled `connection_init` → `start` → `data` → `stop` protocol over `web_socket_channel`). Multiplexed: one socket per process, many subscriptions per socket.

---

## 6 · AI prompt designs

### Photo quality verifier — `photo_quality_analysis.dart`

Run on **every photo step**. Returns `{ verdict, qualityReason, successMessage }`.

Key prompt moves:
- Tells the model the jockey was **shown the example image first**, so rejections can reference it ("उदाहरण जैसा नहीं आया") rather than be abstract.
- Verdict enum forces one of `good`, `blurry`, `dark`, `wrong_subject`, `partial`, `unreadable`.
- Subject match is per-step — tyres step expects a tyre, RC step expects a registration card, etc.
- Tyre detection accepts side-view + partial tread to avoid false rejections in cramped parking.

### RC document — `rc_document_step.dart`

GPT-4o vision. Returns the structured RC fields: registration number, owner, make, model, year, fuel, manufacturing date, registration date, chassis, engine.

After the OCR, the Flutter side cross-checks **booking values vs. RC values** and pops a confirm dialog if they differ — see `_FieldDiff` + `_confirmMismatch` in [`steps/rc_document_step.dart`](../lib/features/inspection_flow/steps/rc_document_step.dart). Mismatch overwrites are explicit, never silent.

### Instrument cluster — `instrument_cluster_step.dart`

GPT-4o vision. Returns `{ kmDriven, warnings[] }`. Warnings decoded from the dashboard tell-tales.

### Test-drive answer parser — `ai/analyzeAnswer`

gpt-4o text. Inputs: transcription, question text, expected values. Outputs `{ value, confidence, notes, acknowledgment }`. Acknowledgment is the **localised confirmation line** the app then reads aloud — "Theek hai, acceleration smooth chalti hai." That's what the driver hears in the closing of each Q.

### Engine sound — `ai/analyzeEngineSound`

`gpt-audio-1.5` (originally `gpt-4o-audio-preview`, swapped due to access). No `response_format: json_object` — model doesn't support it; we use a tolerant `extractJson()` helper that strips markdown fences and chatter.

### Pricing report — `inspections/getInspectionReport`

The big one. Inputs: parent inspection (incl. `quotedPriceInr`), every step's `data` + `aiAnalysis`. Output: `{ pricing, jockeyPitch, bridgeToAsk, nextSteps }`.

Notable contract:
- `pricing.estimatedPriceInr` and the number announced in `jockeyPitch.script` **must match to the rupee**. The prompt restates this twice.
- The script is **currency-in-words** (Devanagari for Hindi, Telugu / Bengali script accordingly). The display card carries the digit form.
- **Bridge-to-ask** segment is conditional: only emitted when `quotedPriceInr` is set AND `estimatedPriceInr < quotedPriceInr`. Issues must be repairable (no year-of-make / km / ownership). Each item carries an approximate fix cost in INR.

### Hindi voice instructions — `prompts/step_intro_prompts.dart`

Not an AI call — these are hand-written per language, per step. Each `StepIntro` has a `display` (what the AI bubble shows) and `spokenSsml` (what ElevenLabs reads). Devanagari throughout for Hindi. The display matches what's spoken so the bubble is a faithful transcript.

---

## 7 · Flutter — state, routing, services

### State (Riverpod, plain `Notifier` / `AsyncNotifier` — no codegen)

The canonical pattern: per-feature providers live in `features/<x>/<x>_provider.dart`. The **auth slice** uses an explicit sealed-class state machine — `AuthState` in [`features/auth/auth_state.dart`](../lib/features/auth/auth_state.dart) — and new async flows follow that pattern rather than ad-hoc booleans.

Key providers:

| Provider | Type | Notes |
| --- | --- | --- |
| `authProvider` | `Notifier<AuthState>` | Sealed states: Initial, Loading, OtpSending, OtpSent, Verifying, Authenticated, Unauthenticated, Error. |
| `languageProvider` | `AsyncNotifier<AppLanguage?>` | SharedPreferences-backed. `null` means "user hasn't picked yet" → route to `/language`. |
| `translationsProvider` | `Provider<Translations>` | Derived from `languageProvider`. |
| `inspectionsAsyncProvider` | `AsyncNotifier<List<Inspection>>` | REST cold-fetch + AppSync live merges (id-match → replace; else prepend). |
| `todaysInspectionsProvider` | `Provider<List<Inspection>>` | Filters to today+future, sorted by time. |
| `inspectionFlowProvider(id)` | `Notifier(id)` | Per-inspection in-flow state: which step, hydrated step row, retry counters. |
| `stepRowsProvider(id)` | `AsyncNotifier(id)` | Cached `/inspections/{id}/steps` result. |
| `assistantUtteranceProvider` | `Notifier<AssistantUtterance?>` | What the AI bar is currently "saying". `say(ssml, display, autoplay)` is the only writer. |
| `inspectionReportProvider(key)` | `AsyncNotifierProvider.family(...)` | Cached by `(id, langCode)` so revisiting the report doesn't refire gpt-4o. |

### Routing (`go_router`, single provider)

```
/splash                  resolves auth → /language or /home
/language                first-time language pick
/login → /otp            OTP flow
/profile (and setup)     profile-setup wizard
/home                    today's inspections + AI bar
/inspection/:id          the 13-step flow shell
/inspection/:id/review   review screen between save and report
/inspection/:id/report   AI pricing + jockey pitch + bridge
```

### Services

| Service | Purpose |
| --- | --- |
| `api/api_client.dart` | Dio with x-api-key + JWT interceptors. |
| `auth_service.dart` + `auth_token_holder.dart` | JWT persistence + request signing. |
| `inspections_service.dart` | All `/inspections/*` calls. |
| `tts_service.dart` | ElevenLabs proxy + audioplayers playback. Singleton; exposes `playerStateStream`. |
| `appsync_subscription.dart` | Hand-rolled WSS client. |
| `language_service.dart` | `LanguageNotifier` + `AppLanguage` enum. |
| `openai_service.dart` | Direct OpenAI proxy (used by some legacy paths — most calls now go through the backend Lambdas). |

---

## 8 · Voice pipeline (TTS + STT)

```
Step intro fires (jockey lands on a step)
   │
   ├─ stepIntroFor(stepId, lang) → { display, spokenSsml }
   ├─ assistantUtteranceProvider.say(spokenSsml, display: display)
   │     │
   │     ├─ TtsService.speak(ssml)
   │     │     ├─ POST /ai/tts → ElevenLabs (voice HH8sIQq8WOcER3Nu118i, speed 0.85)
   │     │     ├─ audioplayers.play(bytes)
   │     │     └─ emits PlayerState stream → bar flips thinking → speaking → done
   │     │
   │     └─ AssistantBottomBar renders the display text + play/pause control
```

For STT (test drive only): WAV 16 kHz mono PCM via `record ^7.0.0`, sent base64 to `/ai/transcribe` with `language` hint. Whisper handles Hindi natively.

Important nuance: `TtsService.speak()` calls `_player.stop()` to flush the previous clip — that emits a `stopped` event BEFORE the new clip plays. The test-drive `_waitForTtsComplete` listener gates on a `startedPlaying` flag so it doesn't treat the pre-play flush as completion.

---

## 9 · Test-drive conversation flow

The whole loop lives in [`steps/test_drive_step.dart`](../lib/features/inspection_flow/steps/test_drive_step.dart). It's the most state-machine-y screen in the app.

```
Tap Start
   │
   └─▶ for each of 7 questions:
         │
         ├─ TTS speaks the localised question (Devanagari for Hindi)
         ├─ Record:
         │    • 500 ms warmup → measure ambient noise (70th-percentile)
         │    • speech threshold = ambient + 8 dB, clamped −50…−20 dBFS
         │    • wait for first sample above threshold (driver started talking)
         │    • once hasSpoken AND elapsed ≥ 1500 ms, watch trailing silence
         │    • 1200 ms (categorical) or 2000 ms (overall) sustained silence → STOP
         │    • duration is the hard ceiling
         ├─ POST /ai/transcribe → Whisper
         ├─ POST /ai/analyze-answer → gpt-4o classification + acknowledgment
         ├─ if `value == "unclear"` and retries left → re-ask (up to 3 attempts)
         ├─ TTS speaks the acknowledgment
         └─ chain into next question (no user tap)
   │
   └─▶ overall open-ended question (same loop, 30 s ceiling, 2 s silence stop)
         │
         └─▶ summary screen → Save & finish → POST media + PATCH step → /report
```

Saved drives revisited later land on the **persisted view** — score header + per-answer rows + per-answer audio playback chips. Hydrated synchronously from `stepRowsProvider` if cached, asynchronously otherwise.

---

## 10 · Image compression strategy

Per-step quality factors (`kCompressionByStep`):
- **Document photos** (RC card, cluster): quality 85 — high detail required for OCR.
- **Exterior photos** (front, sides, rear, roof): quality 75 — composition matters, fine detail less so.

Done **on-device before upload** via `image ^4.2.0` so the backend never sees the raw camera output. Centre-crop after capture so the AI sees the same framing the jockey saw in the viewfinder.

A typical RC capture: 2.4 MP source → 350 KB JPEG. Exterior shot: 600 KB → 220 KB. Result: every `/ai/analyze-image` payload sits well under the 6 MB Lambda request limit.

---

## 11 · Admin UI

Stack: Angular 20 standalone components, signals (no NgRx), Material 20, IBM Plex / Saira fonts.

Pages: Login (placeholder), Dashboard (counts), Inspections list + create, Jockeys list + per-jockey timeline, Tickets, Leads.

Talks to the **same** API Gateway as the app (key auth). The `inspection-create.component.ts` POST is what triggers the AppSync fan-out the demo shows on-screen.

Proxy config: `proxy.conf.json` forwards `/api` → the dev API base URL during local development so cookies / CORS aren't an issue.

---

## 12 · Non-obvious gotchas worth knowing

These are the ones we tripped on. Worth front-loading for any reader picking this up.

1. **AppSync realtime path** is `wss://{realtime-host}/graphql`, NOT `…/graphql/realtime`. Documented incorrectly in older posts.
2. **`response_format: json_object` is not supported by `gpt-audio-1.5`.** Strip it and use a tolerant `extractJson()` helper that handles markdown-fenced or chatter-prefixed responses.
3. **`@aws-sdk/signature-v4` ^3.600.0 doesn't exist on npm.** Use `aws4` (single file, ~30 KB, zero deps) for the publisher Lambda's SigV4 signing. Saves dragging in the full v3 SDK.
4. **SAM build can fail with "Directory not empty `.aws-sam/build`" on macOS.** Race condition. Fix: `rm -rf .aws-sam && npm run deploy:dev`.
5. **`AppTextStyles.button` is NOT const** — `GoogleFonts.inter()` is runtime-resolved. Remove `const` from `Text` widgets that use it.
6. **Outlined buttons with `AppTextStyles.button` need an explicit primary color override**, otherwise the white-on-CTA-dark colour stays and the label is invisible on the white background.
7. **`ElevatedButton.icon` inside a `SizedBox(height: 36)` forces infinite width.** Fix: `minimumSize: Size(0, 36)` + `tapTargetSize: MaterialTapTargetSize.shrinkWrap`.
8. **`Inspection.scheduledAt` is UTC** from the backend; the home card formatter calls `.toLocal()` before formatting time + day comparisons.
9. **TTS playback stop emits a `stopped` event BEFORE the new clip starts.** Wait-for-complete listeners must gate on having seen a `playing` event first or they short-circuit.
10. **Pre-emptive intro on resume of a persisted step is wrong.** `test_drive_step` starts in `_Phase.resolving` and resolves to `intro` OR `persisted` only after the cached step rows land — avoids the AI announcing "Ready for the test drive?" on a screen showing a saved result.

---

> End of LLD. Pair with `HLD.md` for context and `PITCH_DECK.md` for the judging narrative.
