const { randomUUID } = require('crypto');
const { GetCommand, PutCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { created, badRequest, notFound, serverError } = require('/opt/nodejs/lib/response');

const INSPECTIONS_TABLE = process.env.INSPECTIONS_TABLE;
const TICKETS_TABLE = process.env.INSPECTION_TICKETS_TABLE;

const ALLOWED_OUTCOMES = new Set(['accepted', 'countered', 'declined']);

/**
 * POST /inspections/{id}/tickets
 * body: {
 *   outcome:           'accepted' | 'countered' | 'declined',
 *   aiPriceInr:        integer  // the price the AI generated for context
 *   customerPriceInr?: integer  // required when outcome === 'countered'
 *   notes?:            string   // free-text from the jockey (e.g. "owner
 *                                // wants negotiation in person")
 * }
 *
 * Records the customer's decision after the jockey has read out the
 * AI-generated price. Writes one row to InspectionTickets and bumps
 * the parent inspection's status to `completed` (it should already be
 * inProgress when the test drive saves; this is a no-op if it's been
 * completed earlier).
 *
 * Multiple tickets per inspection are allowed — e.g. a customer who
 * countered once but came back to accept later. Each ticket carries
 * its own outcome + timestamp.
 */
exports.handler = async (event) => {
  try {
    const inspectionId = event.pathParameters?.id;
    if (!inspectionId) return badRequest('Missing path param: id');

    const body = safeJson(event.body);
    if (!body) return badRequest('Invalid JSON body');

    const outcome = body.outcome;
    if (!ALLOWED_OUTCOMES.has(outcome)) {
      return badRequest(`Invalid outcome: ${outcome}`);
    }
    const aiPriceInr = intOrNull(body.aiPriceInr);
    if (aiPriceInr === null) {
      return badRequest('Missing or invalid aiPriceInr');
    }
    const customerPriceInr = intOrNull(body.customerPriceInr);
    if (outcome === 'countered' && customerPriceInr === null) {
      return badRequest('customerPriceInr is required when outcome=countered');
    }

    // Confirm the parent inspection exists — keeps the ticket table
    // referentially clean. A 404 here means the jockey is hitting the
    // endpoint with a stale id; surface that rather than silently
    // creating an orphan ticket.
    const parentRes = await ddb.send(new GetCommand({
      TableName: INSPECTIONS_TABLE,
      Key: { id: inspectionId },
    }));
    if (!parentRes.Item) return notFound(`Inspection ${inspectionId} not found`);

    const now = new Date().toISOString();
    const ticket = {
      id: randomUUID(),
      inspectionId,
      outcome,
      aiPriceInr,
      customerPriceInr: customerPriceInr ?? null,
      notes: typeof body.notes === 'string' ? body.notes.trim() : '',
      createdBy: parentRes.Item.assignedTo ?? null,
      createdAt: now,
      // Snapshot of the car attributes at the time the ticket was
      // raised. Lets a backoffice dashboard query tickets without
      // needing a join back to the Inspections row.
      car: {
        title: parentRes.Item.carTitle ?? null,
        model: parentRes.Item.model ?? null,
        yearOfMake: parentRes.Item.yearOfMake ?? null,
        fuelType: parentRes.Item.fuelType ?? null,
        kmDriven: parentRes.Item.kmDriven ?? null,
      },
      customer: {
        name: parentRes.Item.customerName ?? null,
        phone: parentRes.Item.customerPhone ?? null,
      },
    };

    await ddb.send(new PutCommand({
      TableName: TICKETS_TABLE,
      Item: ticket,
    }));

    // Flip the parent to `completed` and stamp outcome + final price
    // so the read-only completed-view in the app can show
    // "Customer countered at ₹X" / "Customer declined" without
    // joining back to the tickets table. For a countered ticket the
    // final price is the customer's counter; for declined we surface
    // the AI's offer as the last number on the table.
    //
    // Soft-fail on the status flip: if a previous call already moved
    // the inspection to completed, the conditional write may collide
    // with concurrent updates — that's fine, the ticket is the
    // authoritative outcome record.
    const finalPriceInr = customerPriceInr ?? aiPriceInr;
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
          ':outcome': outcome,
          ':finalPrice': finalPriceInr,
          ':now': now,
        },
      }));
    } catch (_) {/* ignore */}

    return created(ticket);
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
