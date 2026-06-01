const { UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, unauthorized, serverError } = require('/opt/nodejs/lib/response');
const { requireAuth } = require('/opt/nodejs/lib/auth');

const SESSIONS_TABLE = process.env.SESSIONS_TABLE;

/**
 * POST /auth/logout
 * Header: Authorization: Bearer <jwt>
 *
 * Marks the current session as revoked. We don't delete the row so admin
 * tooling can still see "logged out at X". The JWT remains technically valid
 * until expiry — once we wire session-validity into requireAuth, the token
 * will be rejected.
 */
exports.handler = async (event) => {
  try {
    const claims = await requireAuth(event);
    const sessionId = claims.jti;
    if (!sessionId) return ok({ revoked: false, reason: 'No sessionId in token' });

    const now = new Date().toISOString();
    await ddb.send(new UpdateCommand({
      TableName: SESSIONS_TABLE,
      Key: { sessionId },
      UpdateExpression: 'SET revokedAt = :now',
      ExpressionAttributeValues: { ':now': now },
      ConditionExpression: 'attribute_exists(sessionId)',
    }));

    return ok({ revoked: true, sessionId });
  } catch (err) {
    if (err.statusCode === 401) return unauthorized(err.message);
    if (err.name === 'ConditionalCheckFailedException') return ok({ revoked: false, reason: 'Session not found' });
    return serverError(err);
  }
};
