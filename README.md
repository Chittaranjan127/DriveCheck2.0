<div align="center">

# 🚗 DriveCheck 2.0

### *The voice-and-vision AI copilot that turns a first-day car jockey into a five-year veteran.*

A field evaluator walks up to a seller's car, opens the app, and is guided — **entirely by voice, in their own language** — through a 13-step inspection. Every photo and engine-sound is read by AI in real time, and the app writes the exact negotiation pitch the jockey reads aloud to close the deal.

<br/>

[![Flutter](https://img.shields.io/badge/App-Flutter%203.x-02569B?logo=flutter&logoColor=white)](DriveCheck2.0/)
[![Dart](https://img.shields.io/badge/Dart-Riverpod%20·%20go__router-0175C2?logo=dart&logoColor=white)](DriveCheck2.0/)
[![AWS SAM](https://img.shields.io/badge/Backend-AWS%20SAM-FF9900?logo=amazonaws&logoColor=white)](drivecheck2.0-backend/)
[![Node](https://img.shields.io/badge/Lambda-Node.js%2020%20·%20arm64-339933?logo=nodedotjs&logoColor=white)](drivecheck2.0-backend/)
[![OpenAI](https://img.shields.io/badge/AI-GPT--4o%20·%20Whisper%20·%20ElevenLabs-412991?logo=openai&logoColor=white)](#-the-ai-surface)
[![Languages](https://img.shields.io/badge/Speaks-हिन्दी%20·%20తెలుగు%20·%20বাংলা%20·%20EN-E63946)](#-built-for-the-doorstep)

<sub>Built for **Token '26 · Problem Statement 3**</sub>

</div>

---

## 📦 What's in this monorepo

Two projects, one repo, one history — the mobile app and the cloud that powers it ship together.

| Folder | Stack | Role |
|---|---|---|
| 📱 **[`DriveCheck2.0/`](DriveCheck2.0/)** | Flutter 3.x · Dart · Riverpod · go_router | The iOS + Android app the jockey holds on the doorstep |
| ☁️ **[`drivecheck2.0-backend/`](drivecheck2.0-backend/)** | AWS SAM · Node.js 20 (Lambda, arm64) · DynamoDB · AppSync · S3 | 24 Lambdas behind one API Gateway — auth, inspections, AI proxies, real-time fan-out |

```
DriveCheck2.0  (this repo)
├── 📱 DriveCheck2.0/            ← Flutter app  (jockey + admin)
└── ☁️ drivecheck2.0-backend/    ← AWS SAM serverless backend
```

> 💡 **Why a monorepo?** The app and backend evolve in lockstep — a new inspection step touches a Flutter screen *and* a Lambda *and* a DynamoDB row. One commit can land all three, atomically.

---

## ✨ Why this is interesting

|  |  |
|---|---|
| 🎯 **Real problem** | Used-car field inspections are still done on paper checklists with a personal phone. Quality varies per inspector, pricing is gut-feel, and the seller↔buyer conversation is the weakest link in the funnel. |
| 🧠 **AI is the product, not a decoration** | Every step's data flows through a model. The pricing report doesn't just print a number — it writes the **exact paragraph the jockey reads aloud**, anchored to findings from *this* inspection. |
| 🎙️ **Hands-free where it counts** | The test-drive step is voice-only — the jockey can't look at their phone while driving. We chain **Whisper → GPT-4o → ElevenLabs TTS** so the inspector talks to the car, not the screen. |
| 🏗️ **Built like a product, not a demo** | Full serverless stack: 24 Lambdas, 7 DynamoDB tables, AppSync real-time, S3 media, API Gateway with usage plan + key, IAM least-privilege. One `npm run deploy:dev`. |
| 💬 **The negotiation script is the wow** | DriveCheck treats the buyer's side: the AI is prompted to **anchor low**, lead with negative findings, spell currency in words so TTS reads it naturally — in Hinglish, Telugu, Bengali, or English. |

---

## 🛞 The 13-step inspection — zero typing, all voice

| # | Step | The jockey… | The AI… |
|:--:|---|---|---|
| 1 | **Arrival** | Taps "I'm here" | Reads location aloud, opens Maps |
| 2 | **RC document** | Snaps the registration card | OCR fills owner / year / fuel / RC#; flags mismatches |
| 3 | **Instrument cluster** | Snaps the dashboard | Reads odometer, decodes warning lights |
| 4–11 | **Exterior + interior** | Snaps 8 angles | Photo-quality + subject-match verifier; rejects bad shots |
| 12 | **Engine sound** | 15 s mic recording, hood open | Classifies knock / misfire / abnormal idle |
| 13 | **Test drive** | Drives, hands-free Q&A | Asks 7 questions over the speaker, listens (auto-stop on silence), classifies answers |
| 🏁 | **Report + pitch** | Reads the AI script to the seller | Estimates price, writes the negotiation pitch, lists repairs that bridge to the seller's ask |

---

## 🤖 The AI surface

| Lambda | Model | What it does |
|---|---|---|
| `ai/analyzeImage` | `gpt-4o` (vision) | RC OCR · odometer reading · panel-damage detection |
| `ai/analyzeEngineSound` | `gpt-4o-audio-preview` | 15 s engine clip → `{ verdict, confidence, action }` |
| `ai/transcribeAudio` | `whisper-1` | Hindi-aware voice-answer transcription |
| `ai/analyzeAnswer` | `gpt-4o` | Transcript → categorical answer + spoken acknowledgment |
| `ai/textToSpeech` | ElevenLabs | Voices questions + the final pitch in the chosen language |
| `inspections/report` | `gpt-4o` | **The big one** — full inspection → pricing JSON + jockey script + next steps |

---

## 🌐 Built for the doorstep

The user is a low-tech Hindi speaker. The whole product bends around that:

- 🗣️ **Voice-first** — every instruction is spoken; the drive-time UI needs no taps.
- 🌏 **Four languages** — UI, AI voice, and the negotiation pitch all localise to **Hindi · Telugu · Bengali · English**.
- 🔤 **Romanized Hindi in buttons** (jockeys read it faster), **Devanagari in the AI bar** (the system reads it aloud).
- 🖼️ **On-device photo compression** with per-step quality (documents need detail, exterior needs composition).

---

## 🏛️ How it fits together

```
              ┌──────────────────────┐
              │   📱 Flutter app      │   jockey + admin
              └───────────┬──────────┘
                          │  HTTPS · x-api-key · Bearer JWT
                          ▼
              ┌──────────────────────┐
              │   API Gateway (REST)  │   usage plan + per-stage key
              └───────────┬──────────┘
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
     ┌─────────┐     ┌─────────┐     ┌─────────┐
     │  Auth   │     │ Inspect │     │   AI    │     24 Lambdas
     │  5 fns  │     │ 14 fns  │     │  5 fns  │     (Node 20 · arm64)
     └────┬────┘     └────┬────┘     └────┬────┘
          └───────────────┼───────────────┘
                  ┌────────┼────────┐
                  ▼        ▼        ▼
            ┌──────────┐ ┌──────┐ ┌──────────┐
            │ DynamoDB │ │  S3  │ │ External │
            │ 7 tables │ │ media│ │ AI APIs  │
            └────┬─────┘ └──────┘ └──────────┘
                 │ NEW_IMAGE stream
                 ▼
            ┌──────────┐      mutation      ┌──────────┐  subscription   ┌─────────────┐
            │ publisher│ ─────(SigV4)─────▶ │ AppSync  │ ───(WebSocket)─▶ │ live admin  │
            │  Lambda  │                    │ GraphQL  │                 │  dashboard  │
            └──────────┘                    └──────────┘                 └─────────────┘
```

---

## 🚀 Quick start

> Clone once, get both projects.

```bash
git clone https://github.com/Chittaranjan127/DriveCheck2.0.git
cd DriveCheck2.0
```

<table>
<tr><th>📱 App</th><th>☁️ Backend</th></tr>
<tr valign="top"><td>

```bash
cd DriveCheck2.0
flutter pub get
cp .env.example .env   # fill API + AppSync values
flutter run            # real device: cam/mic/GPS
```

</td><td>

```bash
cd drivecheck2.0-backend
cp .env.example .env   # OPENAI / JWT / ELEVENLABS keys
npm run deploy:dev     # one-shot SAM deploy
```

</td></tr>
</table>

🔐 **Heads-up:** `.env` files are **git-ignored** (they hold real secrets) — they won't come with a clone. Copy each `.env.example` and fill in the values, or pull them from your password manager / CloudFormation stack outputs.

---

## 📚 Dig deeper

| Want to know… | Read |
|---|---|
| App architecture, conventions, the 13 steps | [`DriveCheck2.0/README.md`](DriveCheck2.0/README.md) |
| Backend deploy, every endpoint, AI prompts | [`drivecheck2.0-backend/README.md`](drivecheck2.0-backend/README.md) |
| Pitch / demo storyboard | [`DriveCheck2.0/submission/PITCH_DECK.md`](DriveCheck2.0/submission/PITCH_DECK.md) |
| High-level design (AWS topology, data flow) | [`DriveCheck2.0/submission/HLD.md`](DriveCheck2.0/submission/HLD.md) |
| Low-level design (schemas, contracts, gotchas) | [`DriveCheck2.0/submission/LLD.md`](DriveCheck2.0/submission/LLD.md) |
| Day-to-day code orientation for the app | [`DriveCheck2.0/CLAUDE.md`](DriveCheck2.0/CLAUDE.md) |

---

<div align="center">

**DriveCheck 2.0** — *talk to the car, close the deal.*

<sub>Built for Token '26 · Problem Statement 3 · 2026</sub>

</div>
