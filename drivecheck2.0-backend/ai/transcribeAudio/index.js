const { ok, badRequest, serverError } = require('/opt/nodejs/lib/response');
const { requireAuth } = require('/opt/nodejs/lib/auth');
const { getJsonSecret } = require('/opt/nodejs/lib/secrets');
const logger = require('/opt/nodejs/lib/logger');

const OPENAI_URL = 'https://api.openai.com/v1/audio/transcriptions';
const DEFAULT_MODEL = 'whisper-1';
const ALLOWED_LANGS = new Set(['en', 'hi', 'te', 'bn']);

exports.handler = async (event) => {
  try {
    const auth = await requireAuth(event);
    if (auth.error) return auth.error;

    const body = parseBody(event);
    if (!body) return badRequest('Invalid JSON body');

    const {
      audioBase64,
      language,
      mimeType = 'audio/m4a',
      filename = 'audio.m4a',
      model = DEFAULT_MODEL,
    } = body;
    if (!audioBase64) return badRequest('Missing field: audioBase64');
    const langHint = ALLOWED_LANGS.has(language) ? language : null;

    let OPENAI_API_KEY = process.env.OPENAI_API_KEY;
    if (!OPENAI_API_KEY) {
      ({ OPENAI_API_KEY } = await getJsonSecret(process.env.OPENAI_SECRET_ARN));
    }
    if (!OPENAI_API_KEY || OPENAI_API_KEY === 'replace-me') {
      return serverError(new Error('OpenAI key not configured'));
    }

    const audioBuf = Buffer.from(audioBase64, 'base64');
    if (audioBuf.length === 0) return badRequest('Empty audio payload');

    const form = new FormData();
    form.append('file', new Blob([audioBuf], { type: mimeType }), filename);
    form.append('model', model);
    if (langHint) form.append('language', langHint);
    form.append('response_format', 'json');

    const started = Date.now();
    const res = await fetch(OPENAI_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
      body: form,
    });

    const raw = await res.text();
    if (!res.ok) {
      logger.error('whisper_non_2xx', { status: res.status, body: raw.slice(0, 500) });
      return serverError(new Error(`OpenAI ${res.status}: ${raw.slice(0, 200)}`));
    }

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      logger.warn('whisper_content_not_json', { raw: raw.slice(0, 300) });
      return serverError(new Error('Whisper returned non-JSON'));
    }

    const text = (parsed.text || '').trim();
    logger.info('whisper_ok', {
      model,
      lang: langHint,
      bytes: audioBuf.length,
      chars: text.length,
      latencyMs: Date.now() - started,
    });
    return ok({ text, language: langHint, model });
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
