const { ok, badRequest, serverError } = require('/opt/nodejs/lib/response');
const { requireAuth } = require('/opt/nodejs/lib/auth');
const { getJsonSecret } = require('/opt/nodejs/lib/secrets');
const logger = require('/opt/nodejs/lib/logger');

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
const DEFAULT_MODEL = 'gpt-4o';
// Whisper transcripts of a single answer (~10 seconds) sit well under
// 500 chars; cap at 2 KB so a misrouted prompt or hostile client
// can't pipe War & Peace into the parser.
const MAX_TRANSCRIPT_CHARS = 2000;

const SCRIPT_INSTRUCTION = {
  en: { name: 'English', script: 'Latin (English alphabet)'  },
  hi: { name: 'Hindi',   script: 'Devanagari (देवनागरी)'        },
  te: { name: 'Telugu',  script: 'Telugu (తెలుగు)'            },
  bn: { name: 'Bengali', script: 'Bengali (বাংলা)'            },
};

const ALLOWED_LANGS = new Set(Object.keys(SCRIPT_INSTRUCTION));

/**
 * POST /ai/analyze-answer
 * body: {
 *   transcription:   string  // what Whisper heard
 *   questionText:    string  // the question the user was answering
 *   expectedValues:  string[] // categorical choices (e.g. ["smooth","jerky","sluggish"])
 *   language?:       'en'|'hi'|'te'|'bn'
 * }
 *
 * Parses a transcribed test-drive answer into one of the question's
 * expected categories. Returns the chosen value, a confidence score,
 * any extra detail the driver mentioned, and a short spoken
 * acknowledgment the client can pipe into TTS for the "Got it…" beat.
 */
exports.handler = async (event) => {
  try {
    const auth = await requireAuth(event);
    if (auth.error) return auth.error;

    const body = parseBody(event);
    if (!body) return badRequest('Invalid JSON body');

    const {
      transcription,
      questionText,
      expectedValues,
      language = 'en',
    } = body;
    if (!transcription || typeof transcription !== 'string') {
      return badRequest('Missing transcription');
    }
    if (transcription.length > MAX_TRANSCRIPT_CHARS) {
      return badRequest(`Transcription too long (max ${MAX_TRANSCRIPT_CHARS})`);
    }
    if (!questionText || typeof questionText !== 'string') {
      return badRequest('Missing questionText');
    }
    if (!Array.isArray(expectedValues) || expectedValues.length === 0) {
      return badRequest('Missing expectedValues');
    }
    const langCode = ALLOWED_LANGS.has(language) ? language : 'en';

    let OPENAI_API_KEY = process.env.OPENAI_API_KEY;
    if (!OPENAI_API_KEY) {
      ({ OPENAI_API_KEY } = await getJsonSecret(process.env.OPENAI_SECRET_ARN));
    }
    if (!OPENAI_API_KEY || OPENAI_API_KEY === 'replace-me') {
      return serverError(new Error('OpenAI key not configured'));
    }

    const lang = SCRIPT_INSTRUCTION[langCode];
    const valuesList = expectedValues.map((v) => `"${v}"`).join(', ');
    const prompt = `You are parsing a car-inspection test driver's
spoken answer to one question. The transcription may be in
${lang.name}, English, or a mix; the underlying meaning is what
matters, not the literal phrasing.

Question asked: "${questionText}"
Allowed categorical values: [${valuesList}, "other", "unclear"]

Driver's transcribed answer: "${transcription}"

Return a single valid JSON object with this exact shape. No prose,
no markdown fences, no commentary.

{
  "value":       "<one of the allowed values exactly as written above>",
  "confidence":  <number 0-1, your certainty about the chosen value>,
  "notes":       "<any specific details the driver mentioned beyond the
                 category, in ${lang.name} written in ${lang.script}.
                 Empty string when the driver just answered the question
                 directly. Examples: 'pulling slightly to the left',
                 'jerky on second-gear shift only'>",
  "acknowledgment": "<one short sentence in ${lang.name} (${lang.script})
                    acknowledging what you understood, conversational,
                    no greeting. Example: 'Got it, smooth acceleration.'
                    Used by the client for TTS read-back.>"
}

Rules:
1. Pick "other" only when the driver gave a meaningful answer that
   genuinely doesn't fit any of the allowed values. Don't use it as a
   "not sure" catch-all.
2. Pick "unclear" when the transcription is garbled, empty, or the
   driver didn't actually answer the question (e.g. "what?",
   "huh?", silence). Set confidence below 0.5 in that case.
3. Confidence reflects YOUR certainty about the match, not the
   driver's. A definite "yes the brakes pull left" → 0.95;
   an ambiguous "they feel a bit off" → 0.5.
4. acknowledgment must be in ${lang.name} (${lang.script}) — clients
   feed it straight to ElevenLabs TTS. Keep it tight, one sentence,
   factual.`;

    const payload = {
      model: DEFAULT_MODEL,
      response_format: { type: 'json_object' },
      messages: [{ role: 'user', content: prompt }],
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
      logger.error('analyze_answer_non_2xx', {
        status: res.status,
        body: raw.slice(0, 500),
      });
      return serverError(new Error(`OpenAI ${res.status}: ${raw.slice(0, 200)}`));
    }

    const openaiJson = JSON.parse(raw);
    const content = openaiJson.choices?.[0]?.message?.content;
    if (!content) return serverError(new Error('Empty content from OpenAI'));

    let parsed;
    try {
      parsed = JSON.parse(content);
    } catch {
      logger.warn('analyze_answer_not_json', { content: content.slice(0, 300) });
      return serverError(new Error('OpenAI returned non-JSON'));
    }

    logger.info('analyze_answer_ok', {
      lang: langCode,
      transcriptChars: transcription.length,
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
