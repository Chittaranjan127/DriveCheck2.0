const { GetCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, notFound, unauthorized, serverError } = require('/opt/nodejs/lib/response');
const { requireAuth } = require('/opt/nodejs/lib/auth');

const TABLE = process.env.USERS_TABLE;

/**
 * GET /auth/me
 * Header: Authorization: Bearer <jwt>
 */
exports.handler = async (event) => {
  try {
    const claims = await requireAuth(event);
    const res = await ddb.send(new GetCommand({ TableName: TABLE, Key: { phoneNumber: claims.sub } }));
    if (!res.Item) return notFound('User not found');
    return ok(res.Item);
  } catch (err) {
    if (err.statusCode === 401) return unauthorized(err.message);
    return serverError(err);
  }
};
