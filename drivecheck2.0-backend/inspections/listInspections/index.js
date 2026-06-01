const { QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, serverError } = require('/opt/nodejs/lib/response');

const TABLE = process.env.INSPECTIONS_TABLE;

/**
 * GET /inspections?assignedTo=<phone>&from=<iso>&to=<iso>
 * - With assignedTo: queries the byAssignee GSI in the date range.
 * - Without: full scan (hackathon convenience; do not ship to prod).
 */
exports.handler = async (event) => {
  try {
    const q = event.queryStringParameters ?? {};
    const { assignedTo, from, to } = q;

    if (assignedTo) {
      const res = await ddb.send(new QueryCommand({
        TableName: TABLE,
        IndexName: 'byAssignee',
        KeyConditionExpression: from && to
          ? '#a = :a AND #s BETWEEN :from AND :to'
          : '#a = :a',
        ExpressionAttributeNames: { '#a': 'assignedTo', ...(from && to && { '#s': 'scheduledAt' }) },
        ExpressionAttributeValues: {
          ':a': assignedTo,
          ...(from && to && { ':from': from, ':to': to }),
        },
      }));
      return ok(res.Items ?? []);
    }

    const res = await ddb.send(new ScanCommand({ TableName: TABLE, Limit: 100 }));
    return ok(res.Items ?? []);
  } catch (err) {
    return serverError(err);
  }
};
