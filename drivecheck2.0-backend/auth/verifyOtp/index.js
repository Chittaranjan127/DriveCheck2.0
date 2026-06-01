const { randomUUID } = require('crypto');
const { GetCommand, PutCommand, UpdateCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, badRequest, unauthorized, serverError } = require('/opt/nodejs/lib/response');
const { signToken, ttlInDays, TOKEN_TTL_DAYS } = require('/opt/nodejs/lib/auth');

const USERS_TABLE = process.env.USERS_TABLE;
const OTP_TABLE = process.env.OTP_TABLE;
const SESSIONS_TABLE = process.env.SESSIONS_TABLE;

/**
 * POST /auth/verify-otp
 * body: { phoneNumber, otp, deviceInfo?, fcmToken? }
 *
 * 1. Looks up OTP from UserOTPManager; validates value + expiry
 * 2. Deletes the OTP entry (one-shot)
 * 3. Creates user record if first login
 * 4. Creates a UserSession row (sessionId used as JWT jti for future revocation)
 * 5. Returns { token, user, sessionId }
 */
exports.handler = async (event) => {
  try {
    const body = safeJson(event.body);
    if (!body?.phoneNumber || !body?.otp) {
      return badRequest('Missing fields: phoneNumber, otp');
    }

    // 1) Lookup OTP
    const otpRes = await ddb.send(new GetCommand({
      TableName: OTP_TABLE,
      Key: { phoneNumber: body.phoneNumber },
    }));
    const otpRow = otpRes.Item;
    if (!otpRow) return unauthorized('OTP not requested or expired');

    const nowSec = Math.floor(Date.now() / 1000);
    if (otpRow.ttl && otpRow.ttl < nowSec) {
      // DynamoDB TTL cleanup is best-effort and may lag — enforce here.
      return unauthorized('OTP expired');
    }
    if (otpRow.otp !== body.otp) return unauthorized('Invalid OTP');

    // 2) One-shot — burn the OTP regardless of what happens after.
    await ddb.send(new DeleteCommand({
      TableName: OTP_TABLE,
      Key: { phoneNumber: body.phoneNumber },
    }));

    const now = new Date().toISOString();

    // 3) Upsert user
    const existing = await ddb.send(new GetCommand({
      TableName: USERS_TABLE,
      Key: { phoneNumber: body.phoneNumber },
    }));
    let user;
    if (existing.Item) {
      const upd = await ddb.send(new UpdateCommand({
        TableName: USERS_TABLE,
        Key: { phoneNumber: body.phoneNumber },
        UpdateExpression: 'SET lastLoginAt = :now, updatedAt = :now',
        ExpressionAttributeValues: { ':now': now },
        ReturnValues: 'ALL_NEW',
      }));
      user = upd.Attributes;
    } else {
      // New users default to 'jockey' (the mobile app). The admin
      // portal passes `role: 'admin'` on its verify-otp call so anyone
      // signing up through the dashboard is created as an admin.
      const role = body.role === 'admin' ? 'admin' : 'jockey';
      user = {
        phoneNumber: body.phoneNumber,
        name: null,
        email: null,
        preferredLanguage: null,
        role,
        status: 'active',
        employeeId: null,
        createdAt: now,
        updatedAt: now,
        lastLoginAt: now,
      };
      await ddb.send(new PutCommand({ TableName: USERS_TABLE, Item: user }));
    }

    // 4) Create session
    const sessionId = randomUUID();
    const session = {
      sessionId,
      phoneNumber: body.phoneNumber,
      deviceInfo: body.deviceInfo ?? null,
      fcmToken: body.fcmToken ?? null,
      ipAddress: event.requestContext?.identity?.sourceIp ?? null,
      userAgent: event.headers?.['User-Agent'] ?? event.headers?.['user-agent'] ?? null,
      createdAt: now,
      lastSeenAt: now,
      revokedAt: null,
      ttl: ttlInDays(TOKEN_TTL_DAYS),
    };
    await ddb.send(new PutCommand({ TableName: SESSIONS_TABLE, Item: session }));

    // 5) Sign JWT with jti=sessionId
    const token = await signToken({
      phoneNumber: user.phoneNumber,
      sessionId,
      role: user.role,
    });

    return ok({ token, user, sessionId });
  } catch (err) {
    return serverError(err);
  }
};

function safeJson(s) {
  if (!s) return null;
  try { return JSON.parse(s); } catch { return null; }
}
