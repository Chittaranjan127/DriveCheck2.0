const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { getJsonSecret } = require('./secrets');

const TOKEN_TTL_DAYS = 30;
const OTP_TTL_MINUTES = 5;

async function _jwtSecret() {
  if (process.env.JWT_SECRET) return process.env.JWT_SECRET;
  const { JWT_SECRET } = await getJsonSecret(process.env.AUTH_SECRET_ARN);
  if (!JWT_SECRET) throw new Error('JWT_SECRET not set in auth secret');
  return JWT_SECRET;
}

/**
 * Sign a JWT. `sub` is phoneNumber, `jti` is the sessionId so we can revoke.
 */
async function signToken({ phoneNumber, sessionId, role }) {
  const secret = await _jwtSecret();
  return jwt.sign(
    { role: role ?? 'jockey' },
    secret,
    { subject: phoneNumber, jwtid: sessionId, expiresIn: `${TOKEN_TTL_DAYS}d` },
  );
}

/**
 * Verify the Authorization: Bearer <jwt> header on an API Gateway event.
 * Returns the decoded payload (`{ sub, role, jti, iat, exp }`) or throws.
 */
async function requireAuth(event) {
  const raw = event.headers?.Authorization ?? event.headers?.authorization;
  if (!raw || !raw.startsWith('Bearer ')) {
    const err = new Error('Missing or malformed Authorization header');
    err.statusCode = 401;
    throw err;
  }
  const token = raw.slice('Bearer '.length).trim();
  const secret = await _jwtSecret();
  try {
    return jwt.verify(token, secret);
  } catch (e) {
    const err = new Error('Invalid or expired token');
    err.statusCode = 401;
    throw err;
  }
}

/** Cryptographically random 6-digit OTP as a string. */
function generateOtp() {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}

/** UNIX epoch seconds for `minutes` from now — used as DynamoDB TTL value. */
function ttlInMinutes(minutes) {
  return Math.floor(Date.now() / 1000) + minutes * 60;
}

/** UNIX epoch seconds for `days` from now. */
function ttlInDays(days) {
  return Math.floor(Date.now() / 1000) + days * 86400;
}

module.exports = {
  signToken,
  requireAuth,
  generateOtp,
  ttlInMinutes,
  ttlInDays,
  TOKEN_TTL_DAYS,
  OTP_TTL_MINUTES,
};
