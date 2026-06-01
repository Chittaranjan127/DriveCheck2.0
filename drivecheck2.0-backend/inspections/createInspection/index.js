const { randomUUID } = require('crypto');
const { TransactWriteCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { created, badRequest, serverError } = require('/opt/nodejs/lib/response');
const { INSPECTION_STEPS } = require('/opt/nodejs/lib/inspectionStepDefinitions');

const INSPECTIONS_TABLE = process.env.INSPECTIONS_TABLE;
const STEPS_TABLE = process.env.INSPECTION_STEPS_TABLE;

/**
 * POST /inspections
 * body: {
 *   assignedTo, scheduledAt, carTitle,
 *   model, yearOfMake, fuelType, kmDriven,  // vehicle attributes — used
 *                                           // by the client to compose
 *                                           // the home-card subtitle.
 *                                           // All optional at create time;
 *                                           // RC + cluster steps later
 *                                           // patch in OCR-derived values
 *                                           // via updateStep `parentUpdates`.
 *   quotedPriceInr,           // seller's asking price at booking time
 *                             // (integer ₹). Used as negotiation anchor
 *                             // on the AI report — the model writes a
 *                             // pitch that talks down from this number.
 *                             // Optional; omit when the seller hasn't
 *                             // named a price yet.
 *   area,                     // short label ("Indiranagar, Bengaluru")
 *   address,                  // full street address (optional)
 *   latitude, longitude,      // pickup coordinates (optional, number)
 *   customerName, customerPhone,
 * }
 *
 * Atomically writes the inspection row + one row per step (all pending)
 * into the InspectionSteps table. 14 items per transaction — well under
 * DDB's 100-item limit.
 */
exports.handler = async (event) => {
  try {
    const body = safeJson(event.body);
    if (!body) return badRequest('Invalid JSON body');

    const required = ['assignedTo', 'scheduledAt', 'carTitle', 'area'];
    const missing = required.filter((k) => !body[k]);
    if (missing.length) return badRequest('Missing fields', { missing });

    const now = new Date().toISOString();
    const id = randomUUID();
    const inspection = {
      id,
      assignedTo: body.assignedTo,
      scheduledAt: body.scheduledAt,
      carTitle: body.carTitle,
      // Vehicle attribute seed values. Each is optional; whatever's null
      // here gets backfilled by the RC / instrument-cluster steps later
      // via updateStep `parentUpdates`. The client composes a "model ·
      // year · fuel · km" subtitle from whichever of these are set.
      model: trimOrNull(body.model),
      yearOfMake: intOrNull(body.yearOfMake),
      fuelType: trimOrNull(body.fuelType),
      kmDriven: intOrNull(body.kmDriven),
      // Seller's asking price at booking time. The report screen
      // surfaces it next to our AI estimate, and the pricing prompt
      // uses it as a negotiation anchor (the script defends a number
      // BELOW this).
      quotedPriceInr: intOrNull(body.quotedPriceInr),
      area: body.area,
      address: body.address ?? null,
      latitude: isFiniteNumber(body.latitude) ? Number(body.latitude) : null,
      longitude: isFiniteNumber(body.longitude) ? Number(body.longitude) : null,
      customerName: body.customerName ?? null,
      customerPhone: body.customerPhone ?? null,
      status: 'scheduled',
      stepCount: INSPECTION_STEPS.length,
      completedStepCount: 0,
      createdAt: now,
      updatedAt: now,
    };

    const stepItems = INSPECTION_STEPS.map((s) => ({
      inspectionId: id,
      stepId: s.stepId,
      stepOrder: s.order,
      stepType: s.type,
      section: s.section,
      photoCount: s.photoCount,
      audioSeconds: s.audioSeconds,
      status: 'pending',
      mediaUrls: [],
      data: {},
      notes: '',
      createdAt: now,
      updatedAt: now,
    }));

    await ddb.send(new TransactWriteCommand({
      TransactItems: [
        { Put: { TableName: INSPECTIONS_TABLE, Item: inspection } },
        ...stepItems.map((item) => ({
          Put: { TableName: STEPS_TABLE, Item: item },
        })),
      ],
    }));

    return created({ ...inspection, steps: stepItems });
  } catch (err) {
    return serverError(err);
  }
};

function safeJson(s) {
  if (!s) return null;
  try { return JSON.parse(s); } catch { return null; }
}

function isFiniteNumber(v) {
  return typeof v === 'number' && Number.isFinite(v);
}

function trimOrNull(v) {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t === '' ? null : t;
}

function intOrNull(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isFinite(n) || !Number.isInteger(n)) return null;
  return n;
}
