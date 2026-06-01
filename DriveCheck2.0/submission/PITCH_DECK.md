# DriveCheck — Pitch Deck

> Cars24 AI Inspection Copilot · Token '26 Hackathon · Problem Statement 3
>
> Use this as a slide-by-slide script. Each `##` is one slide.
> Headlines are the slide title; bullets are speaker notes / on-slide bullets.

---

## 1 · Title

**DriveCheck**
*A voice-and-vision AI copilot for Cars24 Car Jockeys.*

Built with Flutter, Node.js on AWS (SAM + Lambda + DynamoDB + AppSync), OpenAI GPT-4o, ElevenLabs.

---

## 2 · Who is a Car Jockey?

- Trained Cars24 evaluator who drives to a customer's home, inspects the car, and quotes a buying price on the spot.
- 20–40 yrs old. Often 10th-pass or below. **Hindi primary**, basic English.
- WhatsApp + YouTube native. Not comfortable with form-heavy apps.
- Works **standing in the sun, hands busy on the car** — can't read long instructions.

> The product is built for *this* user. Every UX choice flows from it.

---

## 3 · The Problem

A Cars24 home inspection today takes **45–60 minutes**, **73 checkpoints**, and is **entirely dependent on the jockey's training and memory**.

Three failure modes Cars24 absorbs every day:

1. **Inconsistency** — two jockeys inspect the same car, return different price quotes.
2. **Onboarding time** — a new jockey needs **weeks** of supervised drives before they're trusted alone.
3. **Negotiation collapse** — jockey has the inspection notes but no script; customer pushes back, the deal dies on the doorstep.

---

## 4 · Solution in one line

> A Hindi-speaking AI copilot that walks the jockey through every photo, every checkpoint, and the final negotiation — **so a first-day jockey can complete the same inspection as a five-year veteran**.

---

## 5 · How it works (jockey's eye view)

The jockey opens the app, taps an inspection, and the app **takes over**. 13 steps, voice-led, hands-free where possible:

| Step | What the jockey does | What the AI does |
| --- | --- | --- |
| **1 · Arrival** | Taps "I'm here" | Reads the location aloud in Hindi, opens Maps |
| **2 · RC Document** | Snaps photo of the registration card | OCR fills owner, year, fuel, RC #; flags mismatches with the booking |
| **3 · Instrument cluster** | Snaps the dashboard | OCR fills odometer + decodes every warning light |
| **4–11 · Exterior + interior photos** | Snaps each of 8 angles | Vision model judges quality (blur, framing, subject); rejects bad photos with spoken reason |
| **12 · Engine sound** | 15 s mic recording, hood open | Audio model classifies engine health, lists detected issues |
| **13 · Test drive** | Drives the car. **Hands-free Q&A.** | Asks 7 questions over the speaker, listens to each spoken answer, classifies it |
| **End** | Sees the AI price + reads the negotiation script out loud | Estimates fair-market price, writes a Hindi pitch defending it, lists *repairs the seller could make to match their asking price* |

**Zero typing. Voice instructions in Hindi throughout.**

---

## 6 · Demo flow (record in this order)

> Script for the demo video. Aim ~90 s.

1. **Home screen** — bottom AI bar greets you by name, lists today's inspections. Tap one.
2. **Step 2 (RC card)** — quick capture. Show the modal example image that auto-closes (5 s countdown). After capture, AI verifies and flags a *make / model mismatch* against the booking — show the confirm dialog.
3. **Step 12 (engine sound)** — tap, recording runs for 15 s, AI returns a verdict + issue chips.
4. **Step 13 (test drive)** — tap Start. App speaks question 1 in Hindi. **Don't touch the screen.** Speak answer, recording auto-stops on silence, AI confirms it back. Skip to question 7 for time.
5. **Report screen** — AI price card with seller's quoted price struck through. Tap *Play pitch* — ElevenLabs reads the negotiation script. Then show the **"How to match the seller's price"** card listing repairable issues.
6. **Admin dashboard (web)** — show a new inspection assigned from the dashboard, **appearing live on the phone in <2 s** via AppSync.

---

## 7 · Architecture — one picture

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

┌─────────────────┐
│ Angular admin   │  ── REST (key) ──▶ same API Gateway
│  (dispatcher)   │
└─────────────────┘
```

> Full HLD: `submission/HLD.md` · LLD: `submission/LLD.md`.

---

## 8 · Tech choices (and why)

| Choice | Why |
| --- | --- |
| **Flutter** | One codebase, native camera + mic + audio playback, sub-2-min hot reload. |
| **Riverpod (no codegen)** | Async state machines map cleanly to the AI pipeline's phases. |
| **AWS SAM + Lambda** | Hackathon = scale to zero, single CloudFormation stack, `npm run deploy:dev` is the entire deploy. |
| **DynamoDB** | Per-row schema fits the inspection-step model; streams give us free real-time. |
| **AppSync (API key + IAM)** | Live updates without managing a WebSocket server. Single shared socket, multiplexed subs. |
| **OpenAI gpt-4o** | Multi-modal in one model — same endpoint reads RC cards, judges photo quality, classifies test-drive answers, and writes the negotiation script. |
| **ElevenLabs** | Most natural Hindi voice we tested. SSML supported, latency ~1–3 s for a typical line. |
| **Romanized Hindi in UI buttons** | Jockeys read romanized Hindi faster than Devanagari. **AI bubble** keeps Devanagari (it's read by the system, not the user). |

---

## 9 · The AI moments to call out on stage

These are the bits worth lingering on — they're what differentiate DriveCheck from "just a checklist app":

1. **Photo-quality verifier** that *references the example image* in its rejection message. The jockey sees the example, then if their shot doesn't match, the AI says "उदाहरण जैसा नहीं आया".
2. **Conversational test drive** — true hands-free. Question → listen → transcribe → classify → confirm. Up to 3 retries on unclear answers. **Recording auto-stops on silence** so there's no fixed 8-second wait.
3. **Negotiation script** that is *built to defend a low offer* — issues first, then bridge-to-ask: *"if you fix the front brakes (~₹4,000) and the engine warning, we can match your asking price."*
4. **Price-in-words contract** — the AI report and the spoken pitch must agree on the price *to the rupee*. The pitch reads "चार लाख बीस हज़ार रुपये" not "4.2 lakh". Single regression test gates every report.
5. **Live updates** — a new inspection assigned from the admin dashboard lands on the jockey's home screen in <2 s. No refresh.

---

## 10 · What this changes for Cars24

| Today | With DriveCheck |
| --- | --- |
| Weeks of supervised onboarding per jockey | **Day one** — first-day jockey runs the same inspection. |
| Quality varies by jockey | Same 13 steps, same AI checks, every time. |
| Inspection notes ≠ negotiation script | Single AI report contains both, in the jockey's language. |
| Mismatches caught at HQ, post-visit | RC + cluster cross-check at capture time. Booking errors caught **on the doorstep**. |
| Dispatcher waits for daily roll-up | Live status on every inspection, every jockey. |

> **Net:** lower onboarding cost, higher quote consistency, fewer dead deals at the door.

---

## 11 · What's next (after the hackathon)

Order, easiest first:

1. **Real SMS gateway** wired into `/auth/request-otp` (today the dev backend returns a `mockOtp` for the demo OTP screen).
2. **Image upload to S3** via presigned URLs (today: in-Lambda base64). Cuts our Lambda payload size and lets the report screen show original photos.
3. **AppSync subscriptions for admin** (we built the publisher; the admin client just needs to subscribe).
4. **Offline-first step queue** — the field-worker spec already calls for this; the per-step Riverpod notifier makes it a small change.
5. **Negotiation post-mortem** — log every accepted vs. countered ticket, train the pricing prompt on real outcomes.

---

## 12 · Team

> Fill with team names, roles, contact.

| Member | Role |
| --- | --- |
| Chittaranjan Das | … |
| … | … |

Repos:
- App: `DriveCheck/`
- Backend: `drivecheck-backend/`
- Admin UI: `drivecheck-admin-ui/`

---

## Appendix · Numbers to drop on stage

- 13 inspection steps, 8 of which are photo capture, 1 audio, 1 hands-free voice Q&A.
- 18 Lambda handlers, 6 DynamoDB tables, 1 AppSync GraphQL API, single SAM stack.
- 4 supported languages: English, Hindi (romanized + Devanagari for AI), Telugu, Bengali.
- AI calls per full inspection: ~12 vision, 7 audio transcriptions, 7 answer parses, 1 engine-sound classification, 1 pricing report — ~28 round-trips, average ~1.5 s each.
- One full inspection's photos compressed on device before upload (RC + RC docs at q=85, exterior at q=75) — keeps backend payloads under 250 KB per call.
