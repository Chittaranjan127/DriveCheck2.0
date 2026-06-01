const { randomUUID } = require('crypto');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const Jimp = require('jimp');

const { ok, badRequest, unauthorized, serverError } = require('/opt/nodejs/lib/response');
const { requireAuth } = require('/opt/nodejs/lib/auth');

const BUCKET = process.env.SELFIES_BUCKET;
const PUBLIC_BASE = process.env.SELFIES_PUBLIC_BASE;
const REGION = process.env.AWS_REGION || 'ap-south-1';

const TARGET_SIZE = 512;         // square crop, 512x512 max
const TARGET_QUALITY = 80;       // JPEG quality (1-100)
const MAX_INPUT_BYTES = 8 * 1024 * 1024; // 8 MB raw image cap

const s3 = new S3Client({ region: REGION });

/**
 * POST /uploads/selfie
 * Header: Authorization: Bearer <jwt>
 * body: { imageBase64, mimeType? }
 *
 * Decodes the base64 image, resizes to a 512x512 cover crop, re-encodes as
 * JPEG, and uploads to S3 under `selfies/{phoneNumber}/{uuid}.jpg`. Returns
 * the permanent public URL the client should PATCH onto /auth/me.
 */
exports.handler = async (event) => {
  try {
    const claims = await requireAuth(event);
    const phoneNumber = claims.sub;

    const body = safeJson(event.body);
    if (!body?.imageBase64) return badRequest('Missing imageBase64');

    const raw = Buffer.from(body.imageBase64, 'base64');
    if (raw.length === 0) return badRequest('Empty image payload');
    if (raw.length > MAX_INPUT_BYTES) {
      return badRequest(`Image too large (max ${MAX_INPUT_BYTES / 1024 / 1024} MB)`);
    }

    const img = await Jimp.read(raw);
    img.cover(TARGET_SIZE, TARGET_SIZE).quality(TARGET_QUALITY);
    const out = await img.getBufferAsync(Jimp.MIME_JPEG);

    const key = `selfies/${phoneNumber}/${randomUUID()}.jpg`;
    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: key,
      Body: out,
      ContentType: 'image/jpeg',
      CacheControl: 'public, max-age=31536000, immutable',
    }));

    return ok({
      url: `${PUBLIC_BASE}/${key}`,
      key,
      bytes: out.length,
    });
  } catch (err) {
    if (err.statusCode === 401) return unauthorized(err.message);
    return serverError(err);
  }
};

function safeJson(s) {
  if (!s) return null;
  try { return JSON.parse(s); } catch { return null; }
}
