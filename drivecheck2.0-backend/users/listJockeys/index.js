const { ScanCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, serverError } = require('/opt/nodejs/lib/response');

const TABLE = process.env.USERS_TABLE;

/**
 * GET /jockeys
 *
 * Lists every user with role === 'jockey' for the admin panel's
 * assignment dropdown + the "Jockeys" page. The Users table is keyed
 * by `phoneNumber` and has no `id` attribute, so we surface
 * `id` = `phoneNumber` (which is also what inspections store in
 * `assignedTo`, keeping the two consistent for the UI).
 *
 * Hackathon convenience: a full Scan with a role filter. The roster
 * is tiny; swap for a `byRole` GSI before prod if it ever grows.
 */
exports.handler = async () => {
  try {
    const res = await ddb.send(new ScanCommand({
      TableName: TABLE,
      FilterExpression: '#role = :jockey',
      ExpressionAttributeNames: { '#role': 'role' },
      ExpressionAttributeValues: { ':jockey': 'jockey' },
      Limit: 200,
    }));

    const jockeys = (res.Items ?? []).map((u) => ({
      ...u,
      id: u.phoneNumber,
      phone: u.phoneNumber,
    }));

    return ok(jockeys);
  } catch (err) {
    return serverError(err);
  }
};
