const { randomUUID } = require('crypto');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

const { ok, badRequest, serverError } = require('/opt/nodejs/lib/response');
const { STEP_IDS } = require('/opt/nodejs/lib/inspectionStepDefinitions');

const BUCKET = process.env.SELFIES_BUCKET;
const PUBLIC_BASE = process.env.SELFIES_PUBLIC_BASE;
const REGION = process.env.AWS_REGION || 'ap-south-1';

const MAX_INPUT_BYTES = 9 * 1024 * 1024; // 9 MB — stays under API Gateway 10 MB

const s3 = new S3Client({ region: REGION });

// MIME → file-extension lookup. Anything not in this table is rejected
// at the boundary so we don't end up writing untyped blobs to S3.
const EXTENSION_BY_MIME = {
  'image/jpeg': 'jpg',
  'image/jpg':  'jpg',
  'image/png':  'png',
  'audio/wav':  'wav',
  'audio/wave': 'wav',
  'audio/x-wav': 'wav',
  'audio/mpeg': 'mp3',
  'audio/mp3':  'mp3',
  'audio/m4a':  'm4a',
  'audio/x-m4a': 'm4a',
  'audio/aac':  'aac',
};

/**
 * POST /inspections/{id}/steps/{stepId}/media
 * body: { mediaBase64 | imageBase64, mimeType? }
 *
 * Uploads a single piece of step media (image OR audio) to S3 and
 * returns its public URL. The client is expected to have already
 * compressed images (kCompressionByStep in the Flutter project); this
 * handler does not resize.
 *
 * `imageBase64` is kept as an alias for `mediaBase64` so the existing
 * photo steps don't need to change. New audio steps (engine sound,
 * etc.) should use `mediaBase64` for clarity.
 *
 * Object key: inspections/{inspectionId}/{stepId}/{uuid}.{ext}
 *
 * The returned URL is suitable to pass into
 * POST /inspections/{id}/steps/{stepId} as part of `mediaUrls`.
 */
exports.handler = async (event) => {
  try {
    const id = event.pathParameters?.id;
    const stepId = event.pathParameters?.stepId;
    if (!id) return badRequest('Missing path param: id');
    if (!stepId) return badRequest('Missing path param: stepId');
    if (!STEP_IDS.has(stepId)) return badRequest(`Unknown stepId: ${stepId}`);

    const body = safeJson(event.body);
    const payload = body?.mediaBase64 ?? body?.imageBase64;
    if (!payload) return badRequest('Missing mediaBase64');

    const raw = Buffer.from(payload, 'base64');
    if (raw.length === 0) return badRequest('Empty media payload');
    if (raw.length > MAX_INPUT_BYTES) {
      return badRequest(`Media too large (max ${MAX_INPUT_BYTES / 1024 / 1024} MB)`);
    }

    const mime = (body.mimeType || 'image/jpeg').toLowerCase();
    const ext = EXTENSION_BY_MIME[mime];
    if (!ext) return badRequest(`Unsupported mimeType: ${mime}`);
    const key = `inspections/${id}/${stepId}/${randomUUID()}.${ext}`;

    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: key,
      Body: raw,
      ContentType: mime,
      CacheControl: 'public, max-age=31536000, immutable',
    }));

    return ok({
      url: `${PUBLIC_BASE}/${key}`,
      key,
      bytes: raw.length,
    });
  } catch (err) {
    return serverError(err);
  }
};

function safeJson(s) {
  if (!s) return null;
  try { return JSON.parse(s); } catch { return null; }
}
