const { PutCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, badRequest, serverError } = require('/opt/nodejs/lib/response');
const { generateOtp, ttlInMinutes, OTP_TTL_MINUTES } = require('/opt/nodejs/lib/auth');
const logger = require('/opt/nodejs/lib/logger');

const OTP_TABLE = process.env.OTP_TABLE;

/**
 * POST /auth/request-otp
 * body: { phoneNumber }
 *
 * Generates a unique 6-digit OTP, stores it in UserOTPManager with a 5-minute
 * TTL (DynamoDB auto-deletes expired rows), and returns it in the response so
 * the in-app SMS banner can show it. When real SMS is wired, stop returning
 * `otp` in the response (or gate on STAGE !== 'prod').
 */
exports.handler = async (event) => {
  try {
    const body = safeJson(event.body);
    if (!body?.phoneNumber) return badRequest('Missing field: phoneNumber');
    if (!/^\d{10}$/.test(body.phoneNumber)) {
      return badRequest('phoneNumber must be 10 digits');
    }

    const otp = generateOtp();
    const now = new Date().toISOString();
    await ddb.send(new PutCommand({
      TableName: OTP_TABLE,
      Item: {
        phoneNumber: body.phoneNumber,
        otp,
        attempts: 0,
        createdAt: now,
        ttl: ttlInMinutes(OTP_TTL_MINUTES),
      },
    }));

    logger.info('otp_issued', { phoneNumber: body.phoneNumber, ttlMin: OTP_TTL_MINUTES });

    return ok({
      sent: true,
      // Returned for demo. Strip in prod once SMS provider is wired.
      mockOtp: process.env.STAGE === 'prod' ? undefined : otp,
      expiresInSeconds: OTP_TTL_MINUTES * 60,
    });
  } catch (err) {
    return serverError(err);
  }
};

function safeJson(s) {
  if (!s) return null;
  try { return JSON.parse(s); } catch { return null; }
}
