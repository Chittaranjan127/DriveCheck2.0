# DriveCheck — High Level Design (HLD)

> Companion to `PITCH_DECK.md` (judge-facing narrative) and `LLD.md` (implementation detail).

This document describes **what the system is** — the major components, who talks to whom, the data flows that matter, and the AWS topology. For schemas, API contracts, AI prompts, and concrete file references, see `LLD.md`.

---

## 1 · Context

| Actor | What they do | Surface |
| --- | --- | --- |
| **Car Jockey** | Visits the customer, runs the 13-step inspection, reads the AI's negotiation pitch, marks the deal accepted or countered. | **Flutter app** (iOS + Android) |
| **Cars24 dispatcher** | Creates inspection rows for the day, picks a jockey, monitors progress, reviews tickets and closed deals. | **Angular admin** (web) |
| **OpenAI** | Vision (RC, cluster, photo-quality), text (test-drive answer parsing, pricing report), audio (engine sound), Whisper (Hindi transcription). | External API |
| **ElevenLabs** | Hindi-capable TTS for every voice instruction + the negotiation script. | External API |
| **AWS** | Hosts everything else: REST API, Lambdas, DynamoDB, AppSync, Secrets Manager. | `ap-south-1` |

There are no other external dependencies. The hackathon constraint *"no Bedrock"* is honoured — every model call is to OpenAI or ElevenLabs over HTTPS.

---

## 2 · Component map

```
                       ┌────────────────────────────┐
                       │       Flutter App          │
                       │  ┌──────────────────────┐  │
                       │  │ Auth (OTP, JWT)      │  │
                       │  │ Riverpod state       │  │
                       │  │ go_router            │  │
                       │  │ Camera + Mic         │  │
                       │  │ ElevenLabs playback  │  │
                       │  │ AppSync WS client    │  │
                       │  └──────────────────────┘  │
                       └─────────────┬──────────────┘
                                     │ HTTPS (JWT + x-api-key)
                                     │ + wss:// (AppSync)
                                     ▼
       ┌──────────────────────────────────────────────────────┐
       │                  AWS  (ap-south-1)                   │
       │                                                      │
       │  API Gateway (REST, API key, usage plan)             │
       │      │                                               │
       │      ▼                                               │
       │  18 Lambdas — Node.js 20, arm64, single layer        │
       │      │       │       │           │                   │
       │      │       │       │           │                   │
       │      ▼       ▼       ▼           ▼                   │
       │  ┌──────┐ ┌──────┐ ┌──────┐  ┌──────────────┐        │
       │  │ Users│ │ Auth │ │Inspec│  │ AI proxies   │        │
       │  │ Sess │ │ OTP  │ │Steps │  │ (OpenAI,     │        │
       │  │      │ │      │ │Tick. │  │  ElevenLabs) │        │
       │  └───┬──┘ └──┬───┘ └──┬───┘  └──────┬───────┘        │
       │      │       │        │             │                │
       │      ▼       ▼        ▼             ▼                │
       │  ┌─────────────────────────┐  ┌──────────────────┐   │
       │  │   DynamoDB              │  │ Secrets Manager  │   │
       │  │   • Users               │  │ • drivecheck/dev │   │
       │  │   • UserOTPManager (TTL)│  │   /openai        │   │
       │  │   • UserSessions (TTL)  │  │ • .../elevenlabs │   │
       │  │   • Inspections (Stream)│  └──────────────────┘   │
       │  │   • InspectionSteps     │                         │
       │  │   • InspectionTickets   │                         │
       │  │   • InspectionLeads     │                         │
       │  └──────────┬──────────────┘                         │
       │             │ DynamoDB Streams                       │
       │             ▼                                        │
       │  ┌────────────────────────┐                          │
       │  │ PublishInspection λ    │                          │
       │  │  → SigV4 → AppSync     │                          │
       │  └──────────┬─────────────┘                          │
       │             ▼                                        │
       │  ┌────────────────────────┐                          │
       │  │ AppSync GraphQL        │                          │
       │  │ • API_KEY (clients)    │                          │
       │  │ • IAM (publisher)      │                          │
       │  │ • Subscription:        │                          │
       │  │   onInspectionsForJockey                          │
       │  └──────────┬─────────────┘                          │
       │             │ wss                                    │
       └─────────────┼────────────────────────────────────────┘
                     │
                     ▼ (back up to the Flutter app)

       ┌─────────────────────────────────┐
       │ Angular admin UI                │
       │ Material 20, signals, standalone│
       │ Talks to the same API Gateway   │
       └─────────────────────────────────┘
```

---

## 3 · Inspection step lifecycle (end-to-end)

This is the **central data flow** — every inspection rides this loop 13 times.

```
Jockey opens step N
   │
   ├─ App reads cached step row from /inspections/{id}/steps (if present)
   │      → already saved? render persisted view, no AI calls
   │
   ├─ Else: AI bar speaks the localised intro (ElevenLabs)
   │   ├─ Auto-pops a 5-second example modal (skipped for audio steps)
   │   │   so the jockey sees what a good capture looks like
   │   └─ Jockey performs the action (photo, audio, voice answer)
   │
   ├─ App PUTs the media to /inspections/{id}/steps/{stepId}/media
   │   → returns a URL (today: in-Lambda persisted; next: S3 presigned)
   │
   ├─ App POSTs to /ai/analyze-image (or /ai/analyze-engine-sound,
   │   /ai/analyze-answer) with the URL or base64 + a step-specific prompt
   │   → Lambda calls OpenAI, returns parsed JSON
   │
   ├─ App PATCHes the step row to /inspections/{id}/steps/{stepId}
   │   with the structured AI result and status="completed"
   │
   └─ DynamoDB Stream fires (Inspections row updated)
        → PublishInspection Lambda
        → SigV4-signed mutation on AppSync
        → onInspectionsForJockey subscription fans out
        → Jockey's home screen (and admin dashboard) update live
```

Two specific steps deviate slightly:

- **Step 2 · RC document** — additionally cross-checks OCR output against the parent inspection's `carTitle`, `model`, `yearOfMake`, `fuelType` and surfaces a confirm dialog before *overwriting* booking-time values.
- **Step 13 · Test drive** — runs a Hindi conversation loop in-app: TTS asks, recorder listens with **voice-activity-detected auto-stop** (silence → submit), Whisper transcribes, gpt-4o classifies into one of the question's expected values, TTS confirms. Loops on `unclear` up to 3 times.

---

## 4 · Real-time architecture

Why we built it:
- Dispatcher creates an inspection at 10:02. Jockey is already in the app. We want it on their screen by 10:02:02 — not on the next pull-to-refresh.
- Same fan-out powers the admin dashboard (jockey marks step 5 complete → admin sees "5/13" tick up).

Why we chose **AppSync over Pusher / Ably / our own socket server**:
- Single managed endpoint, AWS-native (no extra vendor).
- IAM auth lets the publisher Lambda sign mutations without holding the client API key.
- Subscription **arg-based filtering** is built in — `onInspectionsForJockey(assignedTo: "...")` ships only events whose payload matches.
- Free tier covers the hackathon and beyond.

Why we **hand-rolled a tiny WebSocket client** instead of pulling in `amplify_api`:
- We need exactly one subscription. Amplify drags in codegen + auth categories we don't use.
- Total client code: ~210 lines, single file, zero generated code, easy to debug.

Failure modes we accepted:
- API key rotation is manual. The deployed key has 7-day default expiry — we'll rotate before the demo.
- Publisher Lambda retries twice on stream failures. Beyond that, a row update can be missed — clients still see the correct state on their next REST refresh.

---

## 5 · AWS topology

Everything sits in **one CloudFormation stack** (`drivecheck-backend-{stage}`), region `ap-south-1`, deployed via `sam deploy`.

| Resource | Count | Notes |
| --- | --- | --- |
| API Gateway REST API | 1 | API key + usage plan; 18 routes |
| Lambda functions | 18 | Node.js 20, arm64, single shared layer |
| Lambda layer | 1 | `shared/utilities/nodejs/lib/*` — DynamoDB client, response helpers, JWT verify, OpenAI/ElevenLabs helpers |
| DynamoDB tables | 6 | All on-demand. `Inspections` has a Stream (NEW_IMAGE). |
| AppSync GraphQL API | 1 | API_KEY (clients) + AWS_IAM (publisher); 1 mutation, 1 subscription |
| Secrets Manager | 2 | OpenAI + ElevenLabs keys |
| IAM role | 1 | Single execution role used by every Lambda — least-privilege DDB + Secrets Manager + AppSync invoke |
| Tags on every resource | — | `Owner=…`, `Project=drivecheck`, `Env=dev` (hackathon cleanup policy) |

**Budget:** target ≤ $100 across the hackathon. We're tracking well under — pay-per-use on every service, no provisioned capacity, no EC2.

---

## 6 · Security model

| Concern | What we do |
| --- | --- |
| Every API call must carry a project key | API Gateway `x-api-key` required on every route |
| Per-user identity on auth / profile / inspection writes | JWT (`Authorization: Bearer …`), verified inside the Lambda via `requireAuth(event)` |
| OTP brute force | One-shot OTP rows with 5-min TTL; row deleted on first verify |
| Session revocation | `UserSessions` table; `jti` in JWT == `sessionId`; logout sets `revokedAt` |
| Secrets in code | None. Keys live in Secrets Manager, fetched lazily, cached per warm container |
| AppSync write access | Mutation locked to `@aws_iam`; only the publisher Lambda's execution role has the IAM grant on that field — clients can't call it |
| Cross-jockey data leakage | Inspections subscription filters server-side on `assignedTo` (AppSync arg-based filter on the mutation payload) |
| Image content | Today: in-Lambda base64. Next iteration: presigned S3 PUT — images never traverse our backend |

What's deferred:
- WAF on API Gateway — out of scope for the hackathon, easy to add.
- AppSync API key rotation automation — currently manual.
- PII redaction in logs — we don't log request bodies that contain phone numbers.

---

## 7 · Localisation strategy

The app supports **4 languages**: English, Hindi (default, romanized in UI, Devanagari in AI voice bubbles), Telugu, Bengali.

Single source of truth: `lib/core/i18n/translations.dart`. Every visible string is a field on the `Translations` class with one value per language. There is **no Flutter `intl` codegen** — adding a key is one field + four map entries, no codegen step.

Why we deliberately use **romanized Hindi for UI buttons**: jockey research showed they read romanized Hindi faster than Devanagari. The **AI assistant bubble** uses Devanagari because it's read aloud by the system, not by the jockey, and matches what they hear.

The selected language survives across app launches via `SharedPreferences`. On logout it's cleared, so the next sign-in always re-routes the user through the language chooser — important when devices are shared between jockeys.

---

## 8 · Deployment + observability

| Concern | Mechanism |
| --- | --- |
| Deploy | `npm run deploy:dev` (SAM build + deploy, one config) |
| Stack outputs | `ApiBaseUrl`, `ApiKeyId`, AppSync URL + key — copied to `.env` files for the Flutter and Admin apps |
| Logs | `npm run logs:inspections` tails every Lambda; per-Lambda log groups in CloudWatch |
| Realtime debug | Flutter logs every `connect → ack → subscribe → event`; AppSync error payloads are surfaced to subscribers (`[appsync] error id=...`) |
| Soft-fail on AI calls | Pricing report, photo quality, engine sound all soft-fail — the rest of the flow continues, the model's response just shows `null` |
| Tag hygiene | Every CloudFormation resource carries `Owner` + `Project` so the hackathon cleanup script can find them |

---

## 9 · What's intentionally not in scope

- **Offline mode** — the field-worker spec calls for it. We've shaped the data layer (per-step rows, idempotent PATCHes) so it's a small follow-up; not in the demo.
- **Push notifications** — `fcmToken` is captured at OTP verify time, but we don't push yet. Reserved for the dispatcher → jockey "new inspection" ping when the app is backgrounded.
- **Photo storage in S3** — today base64 inside the Lambda payload. Adequate for ≤500 KB compressed photos; next iteration moves to presigned PUTs.
- **Admin auth** — admin UI talks to the API today with the same key. A separate role / Cognito federated identity is the production answer.

---

## 10 · Where to look next

| You want to know… | Go to |
| --- | --- |
| Slide-by-slide pitch | [PITCH_DECK.md](PITCH_DECK.md) |
| API contracts, schemas, prompts | [LLD.md](LLD.md) |
| The product narrative + design tokens | [`FLUTTER_README.md`](../FLUTTER_README.md) (32 KB spec) |
| Backend deploy how-to | [`drivecheck-backend/README.md`](../../drivecheck-backend/README.md) |
| Day-to-day code orientation | [`CLAUDE.md`](../CLAUDE.md) |
