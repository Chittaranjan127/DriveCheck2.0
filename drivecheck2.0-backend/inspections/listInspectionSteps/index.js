const { QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, badRequest, serverError } = require('/opt/nodejs/lib/response');

const STEPS_TABLE = process.env.INSPECTION_STEPS_TABLE;

/**
 * GET /inspections/{id}/steps
 *
 * Returns every step row for the inspection, sorted by stepOrder. With
 * only 13 rows per inspection this fits in a single Query page.
 */
exports.handler = async (event) => {
  try {
    const id = event.pathParameters?.id;
    if (!id) return badRequest('Missing path param: id');

    const res = await ddb.send(new QueryCommand({
      TableName: STEPS_TABLE,
      KeyConditionExpression: '#inspectionId = :id',
      ExpressionAttributeNames: { '#inspectionId': 'inspectionId' },
      ExpressionAttributeValues: { ':id': id },
    }));

    const items = (res.Items ?? []).slice().sort(
      (a, b) => (a.stepOrder ?? 0) - (b.stepOrder ?? 0),
    );
    return ok(items);
  } catch (err) {
    return serverError(err);
  }
};
