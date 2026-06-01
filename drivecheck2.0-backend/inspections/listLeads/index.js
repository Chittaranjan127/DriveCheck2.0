const { ScanCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, serverError } = require('/opt/nodejs/lib/response');

const TABLE = process.env.INSPECTION_LEADS_TABLE;

/**
 * GET /leads?status=<open|forwarded|contacted|closed>
 *
 * Lists every InspectionLead across the platform for the admin
 * "Leads" page. Hackathon convenience: a full Scan (Limit 100),
 * mirroring listInspections. Add a date-keyed GSI before prod if the
 * table grows large.
 */
exports.handler = async (event) => {
  try {
    const status = event.queryStringParameters?.status;

    const res = await ddb.send(new ScanCommand({
      TableName: TABLE,
      Limit: 100,
      ...(status && {
        FilterExpression: '#s = :s',
        ExpressionAttributeNames: { '#s': 'status' },
        ExpressionAttributeValues: { ':s': status },
      }),
    }));

    const items = (res.Items ?? []).sort(
      (a, b) => String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? '')),
    );
    return ok(items);
  } catch (err) {
    return serverError(err);
  }
};
