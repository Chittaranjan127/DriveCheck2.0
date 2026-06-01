const { randomUUID } = require('crypto');
const { GetCommand, PutCommand, UpdateCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { created, badRequest, notFound, serverError } = require('/opt/nodejs/lib/response');

const INSPECTIONS_TABLE = process.env.INSPECTIONS_TABLE;
const STEPS_TABLE = process.env.INSPECTION_STEPS_TABLE;
const LEADS_TABLE = process.env.INSPECTION_LEADS_TABLE;

/**
 * POST /inspections/{id}/leads
 * body: {
 *   agreedPriceInr: integer  // the price the customer agreed to (same
 *                            // as the AI-suggested price in the
 *                            // common happy path)
 *   aiPriceInr:     integer  // what the AI report had recommended
 *   notes?:         string   // free-text from the jockey
 * }
 *
 * Records a closed-loop "customer agreed" outcome. Unlike
 * InspectionTickets (which is for counter-offers / open-ended
 * follow-ups), a Lead is a confirmed deal: the customer said yes at
 * the price the jockey quoted, and Cars24 procurement can pick this
 * up directly. We snapshot the WHOLE inspection (parent + every step
 * row) into the lead so backoffice has a self-contained record
 * without needing to re-fetch from the live inspection tables.
 */
exports.handler = async (event) => {
  try {
    const inspectionId = event.pathParameters?.id;
    if (!inspectionId) return badRequest('Missing path param: id');

    const body = safeJson(event.body);
    if (!body) return badRequest('Invalid JSON body');

    const agreedPriceInr = intOrNull(body.agreedPriceInr);
    const aiPriceInr = intOrNull(body.aiPriceInr);
    if (agreedPriceInr === null) return badRequest('Missing or invalid agreedPriceInr');
    if (aiPriceInr === null)     return badRequest('Missing or invalid aiPriceInr');

    // Pull the parent + all step rows so the lead carries a frozen
    // snapshot — backoffice doesn't need to join back to the live
    // inspection / steps tables, and changes there can't retroactively
    // alter what we agreed to.
    const [parentRes, stepsRes] = await Promise.all([
      ddb.send(new GetCommand({
        TableName: INSPECTIONS_TABLE,
        Key: { id: inspectionId },
      })),
      ddb.send(new QueryCommand({
        TableName: STEPS_TABLE,
        KeyConditionExpression: '#inspectionId = :id',
        ExpressionAttributeNames: { '#inspectionId': 'inspectionId' },
        ExpressionAttributeValues: { ':id': inspectionId },
      })),
    ]);
    if (!parentRes.Item) return notFound(`Inspection ${inspectionId} not found`);
    const inspection = parentRes.Item;
    const steps = (stepsRes.Items ?? []).slice().sort(
      (a, b) => (a.stepOrder ?? 0) - (b.stepOrder ?? 0),
    );

    const now = new Date().toISOString();
    const lead = {
      id: randomUUID(),
      inspectionId,
      agreedPriceInr,
      aiPriceInr,
      notes: typeof body.notes === 'string' ? body.notes.trim() : '',
      createdBy: inspection.assignedTo ?? null,
      createdAt: now,
      // Frozen snapshots of everything the buyer might want to see.
      car: {
        title: inspection.carTitle ?? null,
        model: inspection.model ?? null,
        yearOfMake: inspection.yearOfMake ?? null,
        fuelType: inspection.fuelType ?? null,
        kmDriven: inspection.kmDriven ?? null,
        area: inspection.area ?? null,
      },
      customer: {
        name: inspection.customerName ?? null,
        phone: inspection.customerPhone ?? null,
        address: inspection.address ?? null,
      },
      inspectionSnapshot: {
        status: inspection.status,
        completedStepCount: inspection.completedStepCount ?? steps.length,
        stepCount: inspection.stepCount ?? steps.length,
        steps,
      },
      status: 'open', // open → forwarded → contacted → closed etc.
    };

    await ddb.send(new PutCommand({
      TableName: LEADS_TABLE,
      Item: lead,
    }));

    // Flip the parent to `completed` and stamp the outcome + final
    // price. These extra fields let the home-screen card + the
    // read-only completed-inspection view tell "Customer agreed at ₹X"
    // apart from "Counter-offer ticket" without an extra round-trip
    // to the leads/tickets tables.
    //
    // Soft-fail in case another writer already moved it there (e.g.
    // duplicate submission from a rage-tap on the agreed button).
    try {
      await ddb.send(new UpdateCommand({
        TableName: INSPECTIONS_TABLE,
        Key: { id: inspectionId },
        UpdateExpression: 'SET #status = :completed, '
          + '#outcome = :outcome, '
          + '#finalPrice = :finalPrice, '
          + '#updatedAt = :now',
        ExpressionAttributeNames: {
          '#status': 'status',
          '#outcome': 'outcome',
          '#finalPrice': 'finalPriceInr',
          '#updatedAt': 'updatedAt',
        },
        ExpressionAttributeValues: {
          ':completed': 'completed',
          ':outcome': 'accepted',
          ':finalPrice': agreedPriceInr,
          ':now': now,
        },
      }));
    } catch (_) {/* ignore */}

    return created(lead);
  } catch (err) {
    return serverError(err);
  }
};

function safeJson(s) {
  if (!s) return null;
  try { return JSON.parse(s); } catch { return null; }
}

function intOrNull(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isFinite(n) || !Number.isInteger(n)) return null;
  return n;
}
