const { ScanCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, serverError } = require('/opt/nodejs/lib/response');

const TABLE = process.env.INSPECTION_TICKETS_TABLE;

/**
 * GET /tickets?outcome=<accepted|countered|declined>
 *
 * Lists every InspectionTicket across the platform for the admin
 * "Tickets" page. Hackathon convenience: a full Scan (Limit 100),
 * mirroring listInspections. Add a date-keyed GSI before prod if the
 * table grows large.
 */
exports.handler = async (event) => {
  try {
    const outcome = event.queryStringParameters?.outcome;

    const res = await ddb.send(new ScanCommand({
      TableName: TABLE,
      Limit: 100,
      ...(outcome && {
        FilterExpression: '#o = :o',
        ExpressionAttributeNames: { '#o': 'outcome' },
        ExpressionAttributeValues: { ':o': outcome },
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
