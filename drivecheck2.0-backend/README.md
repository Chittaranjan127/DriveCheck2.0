# DriveCheck — AI-Powered Used Car Inspection

> **Hackathon submission.** Companion mobile app lives at [`../DriveCheck`](../DriveCheck) (Flutter). This repo is the serverless backend.

DriveCheck is an end-to-end used-car inspection product built for the field jockeys at companies like Cars24 / Spinny / Maruti True Value. A jockey walks up to a seller's car, opens the app, and is guided through a structured 13-step inspection. Photos, audio, and voice answers are captured on-device, analysed by AI in real time, and aggregated into a buyer-side pricing report the jockey reads out loud to close the deal.

We ship:

- A guided **13-step inspection flow** (arrival → RC → cluster → engine bay → 5 exterior shots → roof → interior → tyres → engine sound → test drive Q&A)
- An **AI pipeline at every step** — vision (RC OCR, panel damage), audio (engine knock), speech (test-drive Q&A)
- A **multi-language buyer-side pricing engine** that produces a ready-to-read negotiation script in Hindi / Telugu / Bengali / English
- A **hands-free voice loop** for the test-drive step using Whisper + GPT-4o + ElevenLabs TTS
- A **real-time admin dashboard** powered by AppSync GraphQL subscriptions over DynamoDB Streams
- A **closed-loop deal flow** — `Lead` when the customer agrees, `Ticket` when they counter-offer

---

## Why this is interesting

| | |
|---|---|
| **Real problem** | Used-car field inspections are still done on paper checklists with a personal phone. Quality varies per inspector, pricing is gut-feel, and the seller-vs-buyer conversation is the weakest link in the funnel. |
| **AI is the product, not a decoration** | Every step's data flows through a model. The pricing report doesn't just print a number — it writes the **exact paragraph the jockey reads aloud**, anchored to specific findings from this inspection. |
| **Hands-free where it counts** | The test-drive step is voice-only — the jockey can't look at their phone while driving. We chain Whisper → GPT-4o → ElevenLabs TTS so the inspector talks to the car, not the screen. |
| **Built like a product, not a demo** | Full serverless stack: 24 Lambdas, 7 DynamoDB tables, AppSync real-time, S3 media, Secrets Manager, API Gateway with usage plan + API key, IAM least-privilege. Deploys with one `npm run deploy:dev`. |
| **Negotiation script is the wow** | We treat Cars24 as the BUYER. The AI is prompted to **anchor LOW**, lead with negative findings, and never hand the seller free ammunition. The script is in Hinglish (or Telugu / Bengali / English) and currency is spelled in words so TTS reads it correctly. |

---

## Demo accounts

The dev API returns the OTP in the response body, so you don't need real SMS to log in.

| Phone | Role | What they see |
|---|---|---|
| `9999999999` | `admin` | All inspections, tickets, leads, jockeys |
| `7606983009` | `jockey` (Vicky) | 11 inspections: 8 completed across the past month + 3 live ones (Swift in Gurugram, Creta in Noida, Virtus in Aerocity, Sonet in Sec 47 Gurugram) |
| `8888888888` | `jockey` (Chitaranjan) | Empty list |

Login flow:

```bash
# 1) Get OTP — dev returns it in `mockOtp`
curl -s -X POST "$API/auth/request-otp" \
  -H "x-api-key: $KEY" -H "Content-Type: application/json" \
  -d '{"phoneNumber":"7606983009"}'

# 2) Verify → JWT (use the mockOtp from step 1)
curl -s -X POST "$API/auth/verify-otp" \
  -H "x-api-key: $KEY" -H "Content-Type: application/json" \
  -d '{"phoneNumber":"7606983009","otp":"<from above>"}'
```

For the admin user, add `"role":"admin"` to the verify-otp body — the JWT will carry `role: "admin"` and unlock the admin endpoints.

---

## The AI surface

| Lambda | Model | What it does |
|---|---|---|
| `ai/analyzeImage` | `gpt-4o` (vision) | Generic vision proxy. RC document OCR, instrument-cluster odometer reading, panel damage detection. JSON-mode response. |
| `ai/analyzeEngineSound` | `gpt-4o-audio-preview` | Listens to a 15-second engine recording and returns `{ verdict, confidence, recommendedAction }`. Catches knock / misfire / abnormal idle. |
| `ai/transcribeAudio` | `whisper-1` | Voice-answer transcription for the test-drive Q&A flow. |
| `ai/analyzeAnswer` | `gpt-4o` | Takes the transcript + the question + the allowed categorical bucket and picks the answer. Returns a spoken acknowledgment for TTS read-back. |
| `ai/textToSpeech` | ElevenLabs | Voices the AI's questions and the final pricing script in the inspector's chosen language. |
| `inspections/getInspectionReport` | `gpt-4o` | The big one. Takes the entire inspection (parent row + all 13 step rows) and emits **pricing JSON + jockey script + next-step instructions** in the inspector's language. Used by the report screen. |

The pricing prompt is worth opening — it's in [`inspections/getInspectionReport/index.js`](inspections/getInspectionReport/index.js). Highlights:

- Cars24 is framed as the **buyer**, so the script is built to defend a low offer.
- The `script` field is a single flowing paragraph (not bullets) — copy-paste into TTS and the inspector reads straight through.
- Currency must be spelled in words (`"चार लाख बीस हज़ार रुपये"`, not `"₹420000"`) so the TTS read-aloud sounds natural.
- A **price-consistency rule** enforces that the digit shown on the screen card matches the words spoken in the script, with explicit examples in Hindi / Telugu / Bengali.
- `factors` are short English bullets — the jockey's internal cheat-sheet, never read aloud.

---

## The 5-minute inspection walk-through

1. **`POST /inspections`** — admin/jockey creates an inspection with `assignedTo`, `scheduledAt`, `carTitle`, `model`, `yearOfMake`, `fuelType`, `kmDriven`, `quotedPriceInr`, `address`, `latitude`, `longitude`, `customerName`, `customerPhone`. The handler atomically writes the parent row **and one row per step** (all 13) into the steps table — so a missing step row is always a bug, never a "haven't reached it yet" state.
2. **`GET /inspections?assignedTo=7606983009`** — the home screen. Returns the jockey's list, sorted by `scheduledAt`.
3. **`GET /inspections/{id}/steps`** — the flow screen reads the live status of every step.
4. **`POST /inspections/{id}/steps/{stepId}/media`** — uploads photo or audio (base64 in JSON, ≤9 MB, mime whitelist enforced). Returns the public S3 URL.
5. **`POST /inspections/{id}/steps/{stepId}`** — writes the step result: `mediaUrls`, structured `data` (OCR fields, odometer, test-drive answers), `aiAnalysis`, optional `parentUpdates` (whitelisted: `carTitle`, `model`, `yearOfMake`, `fuelType`, `kmDriven`, `carSubtitle` — RC step can patch year/fuel into the home card, cluster step patches km). Auto-bumps `completedStepCount`, flips parent `status` from `scheduled` → `inProgress` on first write.
6. **`GET /inspections/{id}/report?lang=hi`** — the AI pricing report. ~3-8s end-to-end. Pass `lang=en | hi | te | bn` to localise the script.
7. **`POST /inspections/{id}/leads`** — customer agreed: snapshot the inspection + steps onto a Lead row for procurement.
8. **`POST /inspections/{id}/tickets`** — customer countered: write a Ticket with the counter price and reasoning so a manager can decide.

---

## Architecture

```
                  ┌──────────────────┐
                  │  Flutter app     │
                  │  (jockey + admin)│
                  └────────┬─────────┘
                           │ HTTPS + x-api-key + Bearer JWT
                           ▼
                  ┌──────────────────┐
                  │  API Gateway     │  Usage plan + per-stage API key
                  │  (REST, dev)     │
                  └────────┬─────────┘
                           │
       ┌───────────────────┼───────────────────┐
       ▼                   ▼                   ▼
  ┌─────────┐         ┌─────────┐         ┌─────────┐
  │  Auth   │         │ Inspect │         │   AI    │
  │ 5 fns   │         │ 14 fns  │         │ 5 fns   │
  └────┬────┘         └────┬────┘         └────┬────┘
       │                   │                   │
       │  ┌────────────────┼───────────────────┘
       │  │                │
       ▼  ▼                ▼
  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
  │  DynamoDB    │    │  S3 bucket   │    │  Secrets Mgr │
  │  7 tables    │    │ drivecheck-* │    │ auth+openai  │
  └──────┬───────┘    └──────────────┘    └──────────────┘
         │ NEW_IMAGE stream
         ▼
  ┌──────────────┐
  │  Lambda      │
  │ publishInsp. │──── mutation ────▶  ┌──────────────────┐
  └──────────────┘    (SigV4)          │  AppSync         │
                                       │  GraphQL API     │
                                       └────────┬─────────┘
                                                │ subscription
                                                ▼
                                       ┌──────────────────┐
                                       │  Admin dashboard │
                                       │   (live updates) │
                                       └──────────────────┘
```

**DynamoDB tables**

| Table | PK | GSI | TTL | Purpose |
|---|---|---|---|---|
| `DriveCheck-Users-{stage}` | `phoneNumber` | — | — | User profile (name, email, language, role, status) |
| `DriveCheck-UserOTPManager-{stage}` | `phoneNumber` | — | `ttl` (5 min) | One-shot OTPs |
| `DriveCheck-UserSessions-{stage}` | `sessionId` | `byPhoneNumber` | `ttl` (30 d) | Active sessions (`fcmToken`, `deviceInfo`, `revokedAt`, JWT `jti`) |
| `DriveCheck-Inspections-{stage}` | `id` | `byAssignee` | — | Parent inspection — vehicle attrs, location, price quote, status, step counters |
| `DriveCheck-InspectionSteps-{stage}` | `inspectionId, stepId` | — | — | One row per (inspection, step). All 13 seeded at create time |
| `DriveCheck-InspectionTickets-{stage}` | `id` | `byInspection` | — | Counter-offer decisions (customer didn't agree) |
| `DriveCheck-InspectionLeads-{stage}` | `id` | `byInspection` | — | Closed deals (customer agreed). Holds a frozen snapshot of parent + steps |

**Lambdas (24)**

```
auth/         requestOtp  verifyOtp  getMe  updateMe  logout
ai/           analyzeImage  analyzeEngineSound  analyzeAnswer  transcribeAudio  textToSpeech
inspections/  list  get  create  update  uploadStepMedia  listSteps  complete  report
              createTicket  listTickets  listInspectionTickets
              createLead    listLeads    listInspectionLeads
uploads/      uploadSelfie
users/        listJockeys
realtime/     publishInspection (DDB stream → AppSync mutation)
```

All Lambdas share a single execution role (`drivecheck2-0-backend-{stage}-lambda-exec`) with least-privilege policies for the tables, S3 bucket, and Secrets Manager. Shared code (auth, DDB client, response helpers, step definitions) lives in `shared/utilities/nodejs/lib` and ships as a Lambda layer.

---

## Auth model

Two layers:

1. **App-level (API Gateway)** — every request needs `x-api-key: <key>`. Stops random internet traffic and gives us per-key throttling + a usage plan. The Flutter app embeds the key.
2. **User-level (custom JWT)** — issued by `/auth/verify-otp`. 30-day expiry. Carries `sub = phoneNumber`, `role = jockey|admin`, `jti = sessionId`. Verified inside each protected Lambda via `requireAuth(event)` from the shared layer.

The OTP is one-shot, 5-minute TTL via DynamoDB native TTL. Sessions are stored explicitly so we can revoke (`logout` sets `revokedAt`) and audit (`fcmToken`, `deviceInfo`, `ipAddress`, `userAgent`).

---

## Deploy from scratch

```bash
brew install aws-sam-cli
aws configure                       # region: ap-south-1
cp .env.example .env                # fill in OPENAI_API_KEY, JWT_SECRET, ELEVENLABS_API_KEY
npm run deploy:dev
```

`samconfig.toml` carries the parameter overrides and `CAPABILITY_NAMED_IAM` (the shared role uses a custom name).

After deploy, grab outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name drivecheck2-0-backend-dev \
  --query 'Stacks[0].Outputs' --output table

aws apigateway get-api-key --api-key <ApiKeyId> --include-value --query value --output text
```

---

## Try the API end-to-end

```bash
export API=https://<id>.execute-api.ap-south-1.amazonaws.com/dev
export KEY=<resolved api key>
export PHONE=7606983009

# OTP → JWT
OTP=$(curl -s -X POST "$API/auth/request-otp" \
  -H "x-api-key: $KEY" -H "Content-Type: application/json" \
  -d "{\"phoneNumber\":\"$PHONE\"}" | jq -r .data.mockOtp)

TOKEN=$(curl -s -X POST "$API/auth/verify-otp" \
  -H "x-api-key: $KEY" -H "Content-Type: application/json" \
  -d "{\"phoneNumber\":\"$PHONE\",\"otp\":\"$OTP\"}" | jq -r .data.token)

# Jockey's list
curl -s "$API/inspections" \
  -H "x-api-key: $KEY" -H "Authorization: Bearer $TOKEN" | jq

# Grab one completed inspection's id from the list, then:
INSP=<id>

# The AI pricing report — try lang=en / hi / te / bn
curl -s "$API/inspections/$INSP/report?lang=hi" \
  -H "x-api-key: $KEY" -H "Authorization: Bearer $TOKEN" | jq '.data.pricing, .data.jockeyPitch.script'

# Render the spoken pitch as audio
SCRIPT=$(curl -s "$API/inspections/$INSP/report?lang=hi" \
  -H "x-api-key: $KEY" -H "Authorization: Bearer $TOKEN" | jq -r .data.jockeyPitch.script)
curl -s -X POST "$API/ai/tts" \
  -H "x-api-key: $KEY" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"text\":\"$SCRIPT\",\"lang\":\"hi\"}" -o pitch.mp3 && open pitch.mp3
```

For the admin views (all jockeys' work):

```bash
ADMIN_OTP=$(curl -s -X POST "$API/auth/request-otp" \
  -H "x-api-key: $KEY" -H "Content-Type: application/json" \
  -d '{"phoneNumber":"9999999999"}' | jq -r .data.mockOtp)

ADMIN_TOKEN=$(curl -s -X POST "$API/auth/verify-otp" \
  -H "x-api-key: $KEY" -H "Content-Type: application/json" \
  -d "{\"phoneNumber\":\"9999999999\",\"otp\":\"$ADMIN_OTP\",\"role\":\"admin\"}" | jq -r .data.token)

curl -s "$API/jockeys" -H "x-api-key: $KEY" -H "Authorization: Bearer $ADMIN_TOKEN" | jq
curl -s "$API/leads"   -H "x-api-key: $KEY" -H "Authorization: Bearer $ADMIN_TOKEN" | jq
curl -s "$API/tickets" -H "x-api-key: $KEY" -H "Authorization: Bearer $ADMIN_TOKEN" | jq
```

---

## Logs

```bash
npm run logs:ai            # tail any AI Lambda
npm run logs:inspections   # tail every inspections-namespace Lambda
```

Each Lambda emits structured JSON via the shared `logger` helper — `logger.info('event_name', { fields })`. Easy to grep in CloudWatch.

---

## Teardown

```bash
sam delete --stack-name drivecheck2-0-backend-dev --region ap-south-1
```

The S3 bucket has `DeletionPolicy: Retain` (intentional — uploaded inspection photos shouldn't vanish with the stack). Delete it manually if you really mean it.

---

## What we'd do next

- **Push notifications** — the `fcmToken` is stored per session but unused. Wire SNS → FCM for "new inspection assigned" pings.
- **Step-level real-time** — AppSync currently fans out parent inspection changes only. Add the steps table to the stream so the admin dashboard sees granular progress (4/13 → 5/13).
- **Defect taxonomy** — the AI emits free-form `factors`. Bind them to a fixed defect ontology so we can aggregate "% of Swifts with bumper paintwork" across the fleet.
- **Self-test mode** — let the jockey replay a previous inspection on a new car for training, with the AI grading their photo quality / step ordering.
- **Move JWT/OpenAI back into Secrets Manager** — they're currently passed as Lambda env vars to work around an SCP `p-w6hat2sf` deny on Secrets Manager (hackathon-account org policy). DevOps is exempting the Lambda role; once that's live, drop the env-var fallback.

---

## Repo layout

```
.
├── auth/                       OTP issue/verify, profile, logout
├── ai/                         All OpenAI / ElevenLabs proxies
├── inspections/                Inspection CRUD + steps + reports + tickets + leads
├── uploads/                    Selfie upload (separate from step media)
├── users/                      Admin user-list endpoints
├── realtime/                   DDB stream → AppSync publisher
├── shared/utilities/nodejs/    Lambda layer — auth, ddb, response, logger, step defs
├── template.yaml               SAM template — every resource in one file
├── samconfig.toml              Per-stage parameter overrides
└── package.json                Deploy + logs scripts
```

Companion app (Flutter): [`../DriveCheck`](../DriveCheck).
