const { ok, badRequest, serverError } = require('/opt/nodejs/lib/response');
const { getJsonSecret } = require('/opt/nodejs/lib/secrets');
const logger = require('/opt/nodejs/lib/logger');

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
const DEFAULT_MODEL = 'gpt-4o';

exports.handler = async (event) => {
  try {
    const body = parseBody(event);
    if (!body) return badRequest('Invalid JSON body');

    const { prompt, imageBase64, imageUrl, model = DEFAULT_MODEL, mimeType = 'image/jpeg' } = body;
    if (!prompt) return badRequest('Missing field: prompt');
    if (!imageBase64 && !imageUrl) return badRequest('Provide imageBase64 or imageUrl');

    let OPENAI_API_KEY = process.env.OPENAI_API_KEY;
    if (!OPENAI_API_KEY) {
      ({ OPENAI_API_KEY } = await getJsonSecret(process.env.OPENAI_SECRET_ARN));
    }
    if (!OPENAI_API_KEY || OPENAI_API_KEY === 'replace-me') {
      return serverError(new Error('OpenAI key not configured'));
    }

    const imagePart = imageUrl
      ? { type: 'image_url', image_url: { url: imageUrl } }
      : { type: 'image_url', image_url: { url: `data:${mimeType};base64,${imageBase64}` } };

    const payload = {
      model,
      response_format: { type: 'json_object' },
      messages: [
        {
          role: 'user',
          content: [{ type: 'text', text: prompt }, imagePart],
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
      logger.error('openai_non_2xx', { status: res.status, body: raw.slice(0, 500) });
      return serverError(new Error(`OpenAI ${res.status}: ${raw.slice(0, 200)}`));
    }

    const openaiJson = JSON.parse(raw);
    const content = openaiJson.choices?.[0]?.message?.content;
    if (!content) return serverError(new Error('Empty content from OpenAI'));

    let parsed;
    try {
      parsed = JSON.parse(content);
    } catch (e) {
      logger.warn('openai_content_not_json', { content: content.slice(0, 300) });
      return serverError(new Error('OpenAI returned non-JSON content'));
    }

    logger.info('openai_ok', { model, latencyMs: Date.now() - started, usage: openaiJson.usage });
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
