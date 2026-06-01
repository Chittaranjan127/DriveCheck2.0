const { UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, badRequest, notFound, serverError } = require('/opt/nodejs/lib/response');
const { STEP_IDS } = require('/opt/nodejs/lib/inspectionStepDefinitions');

const INSPECTIONS_TABLE = process.env.INSPECTIONS_TABLE;
const STEPS_TABLE = process.env.INSPECTION_STEPS_TABLE;

const ALLOWED_STATUSES = new Set(['pending', 'inProgress', 'completed']);

// Inspection fields a step is allowed to reconcile via parentUpdates.
// Keep this list tight — adding a field here means the step can
// overwrite it on the home card / flow header. Most fields (assignedTo,
// scheduledAt, status, completedStepCount, etc.) must NOT be in here.
//
// String fields: carTitle (make + model), model, fuelType.
// Integer fields: yearOfMake (4-digit year), kmDriven (odometer).
// carSubtitle stays whitelisted for backward compat with any client
// still computing + sending it, even though the Flutter app now derives
// the subtitle from model/year/fuel/km.
const ALLOWED_PARENT_FIELDS = {
  carTitle:    'string',
  carSubtitle: 'string',
  model:       'string',
  fuelType:    'string',
  yearOfMake:  'int',
  kmDriven:    'int',
};

/**
 * POST /inspections/{id}/steps/{stepId}
 * body: { mediaUrls?, data?, status?, notes?, aiAnalysis? }
 *
 * Updates the matching row in InspectionSteps. On transition to
 * status="completed" the row gains completedAt; on first non-pending
 * write the row gains startedAt. Also bumps the parent Inspections row's
 * updatedAt and its completedStepCount so list views can show a quick
 * "X / 13 done" badge without re-querying steps.
 */
exports.handler = async (event) => {
  try {
    const id = event.pathParameters?.id;
    const stepId = event.pathParameters?.stepId;
    if (!id) return badRequest('Missing path param: id');
    if (!stepId) return badRequest('Missing path param: stepId');
    if (!STEP_IDS.has(stepId)) return badRequest(`Unknown stepId: ${stepId}`);

    const body = safeJson(event.body) ?? {};
    if (body.status && !ALLOWED_STATUSES.has(body.status)) {
      return badRequest(`Invalid status: ${body.status}`);
    }

    const now = new Date().toISOString();
    const sets = ['#updatedAt = :now'];
    const exprNames = { '#updatedAt': 'updatedAt' };
    const exprValues = { ':now': now };

    if (Array.isArray(body.mediaUrls)) {
      sets.push('#mediaUrls = :mediaUrls');
      exprNames['#mediaUrls'] = 'mediaUrls';
      exprValues[':mediaUrls'] = body.mediaUrls;
    }
    if (body.data && typeof body.data === 'object') {
      sets.push('#data = :data');
      exprNames['#data'] = 'data';
      exprValues[':data'] = body.data;
    }
    if (body.aiAnalysis && typeof body.aiAnalysis === 'object') {
      sets.push('#aiAnalysis = :aiAnalysis');
      exprNames['#aiAnalysis'] = 'aiAnalysis';
      exprValues[':aiAnalysis'] = body.aiAnalysis;
    }
    if (typeof body.notes === 'string') {
      sets.push('#notes = :notes');
      exprNames['#notes'] = 'notes';
      exprValues[':notes'] = body.notes;
    }

    let becameCompleted = false;
    if (body.status) {
      sets.push('#status = :status');
      exprNames['#status'] = 'status';
      exprValues[':status'] = body.status;
      if (body.status === 'inProgress' || body.status === 'completed') {
        // First-write timestamp; if_not_exists ensures we don't overwrite it
        // when the user revisits the same step.
        sets.push('#startedAt = if_not_exists(#startedAt, :now)');
        exprNames['#startedAt'] = 'startedAt';
      }
      if (body.status === 'completed') {
        sets.push('#completedAt = :now');
        exprNames['#completedAt'] = 'completedAt';
        becameCompleted = true;
      }
    }

    const stepRes = await ddb.send(new UpdateCommand({
      TableName: STEPS_TABLE,
      Key: { inspectionId: id, stepId },
      UpdateExpression: 'SET ' + sets.join(', '),
      ExpressionAttributeNames: exprNames,
      ExpressionAttributeValues: exprValues,
      ConditionExpression: 'attribute_exists(inspectionId)',
      ReturnValues: 'ALL_NEW',
    }));

    // Bump parent inspection: updatedAt always; completedStepCount only
    // when this write flipped the step into "completed" for the first time.
    // (We may double-count if the same step is set to "completed" twice;
    // completeInspection re-validates server-side so the user can't ship
    // a fake-complete inspection on the back of a bad counter.)
    const parentSets = ['#updatedAt = :now'];
    const parentNames = { '#updatedAt': 'updatedAt' };
    const parentValues = { ':now': now };
    if (becameCompleted) {
      parentSets.push('#completedStepCount = if_not_exists(#completedStepCount, :zero) + :one');
      parentNames['#completedStepCount'] = 'completedStepCount';
      parentValues[':zero'] = 0;
      parentValues[':one'] = 1;
    }
    // Reconciled values pushed from the step (e.g., OCR-derived carTitle,
    // RC year + fuel, cluster odometer). Whitelisted by name AND expected
    // type so a malicious client can't overwrite arbitrary fields or
    // poison a string field with an object. Empties/non-finite numbers
    // are dropped so the inspector can't blank out the home card.
    if (body.parentUpdates && typeof body.parentUpdates === 'object') {
      for (const [k, v] of Object.entries(body.parentUpdates)) {
        const expected = ALLOWED_PARENT_FIELDS[k];
        if (!expected) continue;
        let value;
        if (expected === 'string') {
          if (typeof v !== 'string') continue;
          const trimmed = v.trim();
          if (trimmed === '') continue;
          value = trimmed;
        } else if (expected === 'int') {
          // Accept numeric strings as a convenience for clients that
          // serialise everything as text. Reject NaN / Infinity / floats.
          const n = typeof v === 'number' ? v : Number(v);
          if (!Number.isFinite(n) || !Number.isInteger(n)) continue;
          value = n;
        } else {
          continue;
        }
        const namePlaceholder = `#p_${k}`;
        const valuePlaceholder = `:p_${k}`;
        parentSets.push(`${namePlaceholder} = ${valuePlaceholder}`);
        parentNames[namePlaceholder] = k;
        parentValues[valuePlaceholder] = value;
      }
    }
    await ddb.send(new UpdateCommand({
      TableName: INSPECTIONS_TABLE,
      Key: { id },
      UpdateExpression: 'SET ' + parentSets.join(', '),
      ExpressionAttributeNames: parentNames,
      ExpressionAttributeValues: parentValues,
      ConditionExpression: 'attribute_exists(id)',
    }));

    // Separate write so the conditional flip from "scheduled" → "inProgress"
    // doesn't abort the counter bump above. Silently swallow the failure when
    // the parent is already inProgress / completed — that's the expected
    // case for every step write after the first one.
    try {
      await ddb.send(new UpdateCommand({
        TableName: INSPECTIONS_TABLE,
        Key: { id },
        UpdateExpression: 'SET #status = :inProgress',
        ConditionExpression: '#status = :scheduled',
        ExpressionAttributeNames: { '#status': 'status' },
        ExpressionAttributeValues: {
          ':inProgress': 'inProgress',
          ':scheduled': 'scheduled',
        },
      }));
    } catch (err) {
      if (err.name !== 'ConditionalCheckFailedException') throw err;
    }

    return ok(stepRes.Attributes);
  } catch (err) {
    if (err.name === 'ConditionalCheckFailedException') {
      return notFound('Inspection or step does not exist');
    }
    return serverError(err);
  }
};

function safeJson(s) {
  if (!s) return null;
  try { return JSON.parse(s); } catch { return null; }
}
