const { QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, badRequest, serverError } = require('/opt/nodejs/lib/response');

const TABLE = process.env.INSPECTION_LEADS_TABLE;

/**
 * GET /inspections/{id}/leads
 *
 * All leads for one inspection, newest first, via the byInspection
 * GSI (inspectionId HASH + createdAt RANGE).
 */
exports.handler = async (event) => {
  try {
    const inspectionId = event.pathParameters?.id;
    if (!inspectionId) return badRequest('Missing path param: id');

    const res = await ddb.send(new QueryCommand({
      TableName: TABLE,
      IndexName: 'byInspection',
      KeyConditionExpression: '#inspectionId = :id',
      ExpressionAttributeNames: { '#inspectionId': 'inspectionId' },
      ExpressionAttributeValues: { ':id': inspectionId },
      ScanIndexForward: false,
    }));

    return ok(res.Items ?? []);
  } catch (err) {
    return serverError(err);
  }
};
