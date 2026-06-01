const { ok, badRequest, serverError } = require('/opt/nodejs/lib/response');
const { requireAuth } = require('/opt/nodejs/lib/auth');
const { getJsonSecret } = require('/opt/nodejs/lib/secrets');
const logger = require('/opt/nodejs/lib/logger');

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
// Native-audio chat model. Listens to the raw recording rather than a
// speech-to-text intermediate, so engine health cues — knocking,
// ticking, misfires, belt squeal — survive into the model's input.
// Hackathon account currently has access to gpt-audio-1.5; swap via
// the AUDIO_MODEL env var or `model` field in the request body if a
// different audio model is wanted.
const DEFAULT_MODEL = process.env.AUDIO_MODEL || 'gpt-audio-1.5';
// Hard cap so a malformed client (or a malicious one) can't try to
// send minutes of audio. 15 seconds at WAV/16kHz/16-bit ≈ 480 KB raw
// → ~640 KB base64. 2 MB ceiling leaves headroom for higher sample
// rates without exceeding API Gateway's 10 MB request limit.
const MAX_AUDIO_BYTES = 2 * 1024 * 1024;
// gpt-4o-audio-preview officially supports wav + mp3. Validate up
// front so we get a clean 400 instead of a confusing OpenAI error.
const ALLOWED_FORMATS = new Set(['wav', 'mp3']);
const ALLOWED_LANGS = new Set(['en', 'hi', 'te', 'bn']);

const SYSTEM_PROMPT = `You are an automotive mechanic listening to a short
recording of a car engine idling. The recording is from a field car-inspection
app: the jockey holds the phone near the engine bay for ~15 seconds and the
audio captures the engine's running condition. Listen to the recording and
return a single valid JSON object with this exact shape. No prose, no
markdown fences, no commentary.

{
  "quality": "good" | "noisy" | "tooShort" | "wrongAudio" | "silent",
  "qualityReasonDisplay":  "<short on-screen reason — null when quality=='good'>",
  "qualityReasonSpoken":   "<TTS SSML — null when quality=='good'>",

  "engineRunning": true | false,
  "healthScore": <integer 0-100>,
  "verdict": "smooth" | "minorIssue" | "concern" | "criticalIssue" | "inconclusive",

  "detectedIssues": [
    // 0 or more of: "knocking" | "ticking" | "misfire" | "rough_idle"
    //             | "belt_squeal" | "exhaust_leak" | "valve_tap"
    //             | "rattle" | "whistle" | "unusual_vibration"
  ],
  "summaryDisplay": "<short on-screen summary — null when quality!='good'>",
  "summarySpoken":  "<TTS SSML naming the verdict + 1 key cue — null when quality!='good'>"
}

Rules:
1. quality decision tree (stop at first match):
     - The clip contains no audible engine sound at all → "silent".
     - The clip is human speech, music, traffic, or anything other than
       an engine → "wrongAudio".
     - Less than ~5 seconds of actual engine sound → "tooShort".
     - Engine is audible but masked by overwhelming wind / handling
       noise → "noisy".
     - Otherwise → "good".
2. When quality != "good": fill qualityReasonDisplay + qualityReasonSpoken,
   leave summary* null. Set engineRunning=false, healthScore=0,
   verdict="inconclusive", detectedIssues=[].
3. When quality == "good": fill summaryDisplay + summarySpoken, leave
   qualityReason* null. Score honestly — a perfectly smooth modern
   engine is ~95, a healthy older engine with mild valve tick is ~80,
   audible knocking pulls below 50, a misfire pulls below 30.
4. verdict mapping (advisory only — use your judgement):
     score 85-100 → "smooth"
     score 65-84  → "minorIssue"
     score 35-64  → "concern"
     score 0-34   → "criticalIssue"
5. detectedIssues should list every cue you can actually hear — don't
   pad with speculative entries. Empty array is fine when the engine
   sounds smooth.
6. SSML rules for spoken fields: wrap in <speak>...</speak>, one
   <break time="400ms"/> between sentences, conversational, written
   in {LANG_NAME_SCRIPT}. Don't use other SSML tags. summarySpoken
   should name the verdict in plain language ("the engine sounds
   smooth", "I hear some ticking") and end with a polite "please tap
   Next" closer in the same language.
7. Display fields are short status-style strings (≤ 12 words) in
   {LANG_DISPLAY_SCRIPT}.`;

const SCRIPT_INSTRUCTION = {
  en: { name: 'English',  script: 'Latin (English alphabet)'        },
  hi: { name: 'Hindi',    script: 'Devanagari (देवनागरी)'              },
  te: { name: 'Telugu',   script: 'Telugu (తెలుగు)'                  },
  bn: { name: 'Bengali',  script: 'Bengali (বাংলা)'                  },
};

exports.handler = async (event) => {
  try {
    const auth = await requireAuth(event);
    if (auth.error) return auth.error;

    const body = parseBody(event);
    if (!body) return badRequest('Invalid JSON body');

    const {
      audioBase64,
      format = 'wav',
      language = 'en',
      model = DEFAULT_MODEL,
    } = body;
    if (!audioBase64) return badRequest('Missing field: audioBase64');
    if (!ALLOWED_FORMATS.has(format)) {
      return badRequest(`Unsupported format: ${format} (allowed: wav, mp3)`);
    }
    const langCode = ALLOWED_LANGS.has(language) ? language : 'en';

    const audioBuf = Buffer.from(audioBase64, 'base64');
    if (audioBuf.length === 0) return badRequest('Empty audio payload');
    if (audioBuf.length > MAX_AUDIO_BYTES) {
      return badRequest(
        `Audio too large: ${audioBuf.length} bytes (max ${MAX_AUDIO_BYTES})`,
      );
    }

    let OPENAI_API_KEY = process.env.OPENAI_API_KEY;
    if (!OPENAI_API_KEY) {
      ({ OPENAI_API_KEY } = await getJsonSecret(process.env.OPENAI_SECRET_ARN));
    }
    if (!OPENAI_API_KEY || OPENAI_API_KEY === 'replace-me') {
      return serverError(new Error('OpenAI key not configured'));
    }

    const lang = SCRIPT_INSTRUCTION[langCode];
    const prompt = SYSTEM_PROMPT
      .replace('{LANG_NAME_SCRIPT}', `${lang.name} written in ${lang.script}`)
      .replace('{LANG_DISPLAY_SCRIPT}', lang.script);

    const payload = {
      model,
      // gpt-audio-1.5 does NOT support response_format: json_object. The
      // prompt instructs JSON-only output and `extractJson` below copes
      // with markdown fences / leading chatter if the model strays.
      // Audio-input modality lets the model "hear" the recording
      // directly rather than receiving a text transcript first.
      modalities: ['text'],
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            {
              type: 'input_audio',
              input_audio: { data: audioBase64, format },
            },
          ],
        },
      ],
    };

    const started = Date.now();
    const res = await fetch(OPENAI_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    const raw = await res.text();
    if (!res.ok) {
      logger.error('openai_audio_non_2xx', {
        status: res.status,
        body: raw.slice(0, 500),
      });
      return serverError(
        new Error(`OpenAI ${res.status}: ${raw.slice(0, 200)}`),
      );
    }

    const openaiJson = JSON.parse(raw);
    const content = openaiJson.choices?.[0]?.message?.content;
    if (!content) return serverError(new Error('Empty content from OpenAI'));

    const parsed = extractJson(content);
    if (!parsed) {
      logger.warn('openai_audio_content_not_json', {
        content: content.slice(0, 300),
      });
      return serverError(new Error('OpenAI returned non-JSON content'));
    }

    logger.info('openai_audio_ok', {
      model,
      lang: langCode,
      bytes: audioBuf.length,
      latencyMs: Date.now() - started,
      usage: openaiJson.usage,
    });
    return ok(parsed);
  } catch (err) {
    return serverError(err);
  }
};

function parseBody(event) {
  if (!event?.body) return null;
  try {
    return event.isBase64Encoded
      ? JSON.parse(Buffer.from(event.body, 'base64').toString('utf8'))
      : JSON.parse(event.body);
  } catch {
    return null;
  }
}

/// Pulls a JSON object out of a model response that may be wrapped in
/// ```json fences, prefixed with chatter, or both. Without
/// response_format=json_object some models slip back into prose; this
/// keeps the Lambda's contract intact rather than 500-ing the caller.
function extractJson(content) {
  if (typeof content !== 'string') return null;
  let s = content.trim();
  // Strip ```json … ``` or ``` … ``` fences if the model wrapped its
  // answer. The captured group is the inner payload.
  const fence = s.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (fence) s = fence[1].trim();
  // Direct parse — happiest path.
  try { return JSON.parse(s); } catch { /* fall through */ }
  // Fallback: locate the outermost {...} block and try that. Handles
  // "Here's the analysis: { ... } Let me know if you need more!" cases.
  const first = s.indexOf('{');
  const last = s.lastIndexOf('}');
  if (first !== -1 && last > first) {
    try { return JSON.parse(s.slice(first, last + 1)); } catch { /* */ }
  }
  return null;
}
