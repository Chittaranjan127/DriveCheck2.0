const { ok, badRequest, serverError } = require('/opt/nodejs/lib/response');

const ELEVENLABS_URL = 'https://api.elevenlabs.io/v1/text-to-speech';
// Default ElevenLabs voice. Swap by passing `voiceId` in the request
// body if a different voice is wanted for a specific call.
const DEFAULT_VOICE_ID = 'HH8sIQq8WOcER3Nu118i';
const DEFAULT_MODEL = 'eleven_multilingual_v2';
// Keep a tight ceiling — the spoken quality-reason from the RC step is
// expected to be 1-2 sentences. Anything longer is probably accidental
// (e.g., the whole prompt got piped in) and burns ElevenLabs credits.
const MAX_TEXT_LENGTH = 800;

/**
 * POST /ai/tts
 * body: { text, voiceId?, modelId? }
 *
 * Proxies ElevenLabs text-to-speech and returns the MP3 as base64 JSON
 * (same envelope as analyzeImage). Returning base64 over JSON sidesteps
 * API Gateway binary-content negotiation; payloads stay under a few
 * hundred KB for short utterances.
 */
exports.handler = async (event) => {
  try {
    const body = parseBody(event);
    if (!body?.text) return badRequest('Missing text');
    if (typeof body.text !== 'string') return badRequest('text must be a string');
    if (body.text.length > MAX_TEXT_LENGTH) {
      return badRequest(`Text too long (max ${MAX_TEXT_LENGTH} chars)`);
    }

    const apiKey = process.env.ELEVENLABS_API_KEY;
    if (!apiKey || apiKey === 'replace-me') {
      return serverError(new Error('ElevenLabs key not configured'));
    }

    const voiceId = body.voiceId || DEFAULT_VOICE_ID;
    const modelId = body.modelId || DEFAULT_MODEL;

    const res = await fetch(`${ELEVENLABS_URL}/${voiceId}`, {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
        Accept: 'audio/mpeg',
      },
      body: JSON.stringify({
        text: body.text,
        model_id: modelId,
        voice_settings: {
          stability: 0.5,
          similarity_boost: 0.75,
          style: 0.0,
          use_speaker_boost: true,
          // 1.0 = native speed. The default was perceived as too fast for
          // low-literacy jockeys following the audio; 0.85 gives a slower,
          // more deliberate cadence without sounding dragged-out.
          speed: 0.85,
        },
      }),
    });

    if (!res.ok) {
      const errText = (await res.text()).slice(0, 400);
      return serverError(new Error(`ElevenLabs ${res.status}: ${errText}`));
    }

    const buf = Buffer.from(await res.arrayBuffer());
    return ok({
      audioBase64: buf.toString('base64'),
      mimeType: 'audio/mpeg',
      bytes: buf.byteLength,
      voiceId,
      modelId,
    });
  } catch (err) {
    return serverError(err);
  }
};

function parseBody(event) {
  if (!event?.body) return null;
  try { return JSON.parse(event.body); } catch { return null; }
}
