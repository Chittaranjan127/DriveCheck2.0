const { QueryCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, badRequest, notFound, serverError } = require('/opt/nodejs/lib/response');

const INSPECTIONS_TABLE = process.env.INSPECTIONS_TABLE;
const STEPS_TABLE = process.env.INSPECTION_STEPS_TABLE;

/**
 * POST /inspections/{id}/complete
 *
 * Server-side gate: scans every step row for the inspection and only
 * marks the inspection completed if every single step is completed.
 * Returns 400 + the list of pending stepIds otherwise so the client can
 * jump the jockey straight to them.
 */
exports.handler = async (event) => {
  try {
    const id = event.pathParameters?.id;
    if (!id) return badRequest('Missing path param: id');

    const stepRes = await ddb.send(new QueryCommand({
      TableName: STEPS_TABLE,
      KeyConditionExpression: '#inspectionId = :id',
      ProjectionExpression: 'stepId, #status, stepOrder',
      ExpressionAttributeNames: { '#inspectionId': 'inspectionId', '#status': 'status' },
      ExpressionAttributeValues: { ':id': id },
    }));

    const steps = stepRes.Items ?? [];
    if (steps.length === 0) {
      return notFound(`No steps found for inspection ${id}`);
    }

    const pending = steps
      .filter((s) => s.status !== 'completed')
      .sort((a, b) => (a.stepOrder ?? 0) - (b.stepOrder ?? 0))
      .map((s) => s.stepId);

    if (pending.length > 0) {
      return badRequest('Inspection has incomplete steps', { pendingSteps: pending });
    }

    const now = new Date().toISOString();
    const res = await ddb.send(new UpdateCommand({
      TableName: INSPECTIONS_TABLE,
      Key: { id },
      UpdateExpression: 'SET #status = :completed, #completedAt = :now, #updatedAt = :now',
      ExpressionAttributeNames: {
        '#status': 'status',
        '#completedAt': 'completedAt',
        '#updatedAt': 'updatedAt',
      },
      ExpressionAttributeValues: {
        ':completed': 'completed',
        ':now': now,
      },
      ConditionExpression: 'attribute_exists(id)',
      ReturnValues: 'ALL_NEW',
    }));

    return ok(res.Attributes);
  } catch (err) {
    if (err.name === 'ConditionalCheckFailedException') {
      return notFound('Inspection does not exist');
    }
    return serverError(err);
  }
};
