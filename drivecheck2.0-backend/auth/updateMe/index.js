const { UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, badRequest, unauthorized, serverError } = require('/opt/nodejs/lib/response');
const { requireAuth } = require('/opt/nodejs/lib/auth');

const TABLE = process.env.USERS_TABLE;
const ALLOWED_FIELDS = ['name', 'email', 'preferredLanguage', 'employeeId', 'selfieUrl'];
const ALLOWED_LANGUAGES = ['english', 'hindi', 'telugu', 'bengali'];

/**
 * PATCH /auth/me
 * Header: Authorization: Bearer <jwt>
 * body: any subset of { name, email, preferredLanguage, employeeId }
 */
exports.handler = async (event) => {
  try {
    const claims = await requireAuth(event);
    const body = safeJson(event.body);
    if (!body || typeof body !== 'object') return badRequest('Invalid JSON body');

    const updates = {};
    for (const key of ALLOWED_FIELDS) {
      if (key in body) updates[key] = body[key];
    }
    if (Object.keys(updates).length === 0) {
      return badRequest('No allowed fields in body', { allowed: ALLOWED_FIELDS });
    }
    if (updates.preferredLanguage && !ALLOWED_LANGUAGES.includes(updates.preferredLanguage)) {
      return badRequest('Invalid preferredLanguage', { allowed: ALLOWED_LANGUAGES });
    }
    if (updates.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(updates.email)) {
      return badRequest('Invalid email');
    }

    const now = new Date().toISOString();
    const setParts = ['updatedAt = :now'];
    const exprValues = { ':now': now };
    const exprNames = {};
    for (const [k, v] of Object.entries(updates)) {
      const placeholder = `#${k}`;
      const valuePlaceholder = `:${k}`;
      setParts.push(`${placeholder} = ${valuePlaceholder}`);
      exprNames[placeholder] = k;
      exprValues[valuePlaceholder] = v;
    }

    const res = await ddb.send(new UpdateCommand({
      TableName: TABLE,
      Key: { phoneNumber: claims.sub },
      UpdateExpression: 'SET ' + setParts.join(', '),
      ExpressionAttributeNames: Object.keys(exprNames).length ? exprNames : undefined,
      ExpressionAttributeValues: exprValues,
      ConditionExpression: 'attribute_exists(phoneNumber)',
      ReturnValues: 'ALL_NEW',
    }));

    return ok(res.Attributes);
  } catch (err) {
    if (err.statusCode === 401) return unauthorized(err.message);
    if (err.name === 'ConditionalCheckFailedException') return badRequest('User does not exist');
    return serverError(err);
  }
};

function safeJson(s) {
  if (!s) return null;
  try { return JSON.parse(s); } catch { return null; }
}
