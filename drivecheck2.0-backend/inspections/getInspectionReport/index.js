const { GetCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, notFound, badRequest, serverError } = require('/opt/nodejs/lib/response');
const { getJsonSecret } = require('/opt/nodejs/lib/secrets');
const logger = require('/opt/nodejs/lib/logger');

const INSPECTIONS_TABLE = process.env.INSPECTIONS_TABLE;
const STEPS_TABLE = process.env.INSPECTION_STEPS_TABLE;

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
const PRICING_MODEL = 'gpt-4o';

// Language → name + script the AI should write its copy in. Used to
// localise every customer-facing copy field in the report (jockey
// pitch + next steps). Factor bullets stay in English — they're the
// jockey's internal cheat-sheet, not for reading aloud.
const LANGUAGES = {
  en: { name: 'English', script: 'Latin (English alphabet)'    },
  hi: { name: 'Hindi',   script: 'Devanagari (देवनागरी)'          },
  te: { name: 'Telugu',  script: 'Telugu (తెలుగు)'              },
  bn: { name: 'Bengali', script: 'Bengali (বাংলা)'              },
};

/**
 * GET /inspections/{id}/report
 *
 * Pulls the parent inspection + every step row, then asks gpt-4o to:
 *   1. Estimate a fair Indian used-car asking price (range + recommended
 *      single number) based on the structured data collected.
 *   2. Write a short, convincing summary the jockey can read out loud
 *      when explaining the price to the customer.
 *   3. Spell out the next steps the jockey should take after the
 *      customer sees the price.
 *
 * Returns the structured report; the client renders it on the
 * InspectionReport screen, then either submits a ticket with the AI
 * price (customer accepted) or with a counter-offer (customer
 * negotiated) via POST /inspections/{id}/tickets.
 */
exports.handler = async (event) => {
  try {
    const id = event.pathParameters?.id;
    if (!id) return badRequest('Missing path param: id');
    // Language is a query param so the same Lambda can be re-hit when
    // the jockey switches the app language mid-flow. Defaults to
    // English when missing or unsupported.
    const langCode = LANGUAGES[event.queryStringParameters?.lang]
        ? event.queryStringParameters.lang
        : 'en';

    const [parentRes, stepsRes] = await Promise.all([
      ddb.send(new GetCommand({ TableName: INSPECTIONS_TABLE, Key: { id } })),
      ddb.send(new QueryCommand({
        TableName: STEPS_TABLE,
        KeyConditionExpression: '#inspectionId = :id',
        ExpressionAttributeNames: { '#inspectionId': 'inspectionId' },
        ExpressionAttributeValues: { ':id': id },
      })),
    ]);
    if (!parentRes.Item) return notFound(`Inspection ${id} not found`);
    const inspection = parentRes.Item;
    const steps = (stepsRes.Items ?? []).slice().sort(
      (a, b) => (a.stepOrder ?? 0) - (b.stepOrder ?? 0),
    );
    const completed = steps.filter((s) => s.status === 'completed').length;
    const totalSteps = steps.length || 13;
    const naiveScore = Math.round((completed / totalSteps) * 100);

    // Distil the verbose step data into a compact, model-friendly
    // briefing. We strip mediaUrls (the model can't see images here
    // anyway) and keep only the structured `data` / `aiAnalysis`
    // fields each step persisted.
    const stepBriefing = steps.map((s) => ({
      stepId: s.stepId,
      stepType: s.stepType,
      status: s.status,
      data: s.data ?? {},
      aiAnalysis: s.aiAnalysis ?? null,
      notes: s.notes ?? '',
    }));

    const car = {
      title: inspection.carTitle,
      model: inspection.model ?? null,
      yearOfMake: inspection.yearOfMake ?? null,
      fuelType: inspection.fuelType ?? null,
      kmDriven: inspection.kmDriven ?? null,
      area: inspection.area ?? null,
      // Seller's asking price from the booking. Passed to the model
      // as the anchor it's negotiating down from; also surfaced to
      // the client so the report card can show "Quoted: ₹X" next to
      // the AI estimate.
      quotedPriceInr: intOrNull(inspection.quotedPriceInr),
    };

    // Generate the AI-driven pricing + pitch. Soft-fail: if the model
    // call breaks (rate limit, transient OpenAI error, missing key),
    // we still return the structured data so the client can render
    // SOMETHING useful — just without the AI-augmented bits.
    let aiBundle = null;
    try {
      aiBundle = await generateAiBundle({ car, stepBriefing, langCode });
    } catch (err) {
      logger.warn('report_ai_failed', { err: err.message });
    }

    return ok({
      id: inspection.id,
      car,
      customer: {
        name: inspection.customerName ?? null,
        phone: inspection.customerPhone ?? null,
        address: inspection.address ?? null,
      },
      status: inspection.status,
      stepsCompleted: completed,
      totalSteps,
      score: naiveScore,
      steps,
      pricing: aiBundle?.pricing ?? null,
      marketReference: aiBundle?.marketReference ?? null,
      jockeyPitch: aiBundle?.jockeyPitch ?? null,
      bridgeToAsk: aiBundle?.bridgeToAsk ?? null,
      nextSteps: aiBundle?.nextSteps ?? null,
      generatedAt: new Date().toISOString(),
    });
  } catch (err) {
    return serverError(err);
  }
};

async function generateAiBundle({ car, stepBriefing, langCode }) {
  let OPENAI_API_KEY = process.env.OPENAI_API_KEY;
  if (!OPENAI_API_KEY) {
    ({ OPENAI_API_KEY } = await getJsonSecret(process.env.OPENAI_SECRET_ARN));
  }
  if (!OPENAI_API_KEY || OPENAI_API_KEY === 'replace-me') {
    throw new Error('OpenAI key not configured');
  }

  const lang = LANGUAGES[langCode];
  const prompt = `You are pricing an Indian used car based on a Cars24
field inspection AND writing a ready-to-read negotiation script for
the field jockey. Cars24 is the BUYER — the jockey wants to acquire
the car at the lowest defensible price the seller will accept. Use
your knowledge of typical Indian used-car prices (OLX, Cars24, Spinny,
Maruti True Value) for the given make + model + year + km + condition
signals. All prices in Indian Rupees (INR).

Vehicle (note \`quotedPriceInr\` — that's what the SELLER asked for
at booking time; treat it as their anchor and aim to talk them DOWN
from it. If quotedPriceInr is null, ignore it):
${JSON.stringify(car, null, 2)}

Inspection steps (each row's structured \`data\` + \`aiAnalysis\` is
the truth of what was captured / observed):
${JSON.stringify(stepBriefing, null, 2)}

Return a single valid JSON object with this exact shape. No prose, no
markdown fences, no commentary.

{
  "pricing": {
    "estimatedPriceInr": <integer, the recommended OFFER price — sit
                          slightly below fair-market mid so there's
                          room to come up during negotiation>,
    "rangeLowInr":       <integer, conservative end of fair-market
                          range (worst plausible auction value)>,
    "rangeHighInr":      <integer, top of fair-market range>,
    "confidence":        <number 0-1, your certainty given how complete
                          the inspection data is>,
    "factors": [
      // 3-6 short bullets naming what pushed the price down. Lead with
      // the issues, not the positives — they're the negotiation levers
      // the jockey scans before reading the pitch. Each must reference
      // a real finding from the inspection data. Written in ${lang.name}
      // using ${lang.script}. Standard auto terms (engine, brake, RC,
      // km) can stay English — that's how Indian sellers naturally
      // hear them. Numbers stay as digits (₹6,000 / 84,000 km).
    ]
  },
  "marketReference": {
    // Independent of the inspection-adjusted estimate above. What does
    // a CONDITION-NEUTRAL ${car.model ?? 'car'} of this year, fuel and
    // km typically transact at on the Indian used-car market (OLX /
    // Cars24 / Spinny / Maruti True Value listings)? Use your model
    // knowledge of typical Indian listings — no web lookups. Acts as
    // a sanity ceiling and the line the jockey cites when the seller
    // is anchoring far above reality (e.g. ₹1 Cr quoted for a WagonR).
    "rangeLowInr":  <integer, low end of the typical listing range>,
    "rangeHighInr": <integer, high end of the typical listing range>,
    "basis": "<one short phrase the jockey can read aloud, in
              ${lang.name} using ${lang.script}, naming what the range
              is grounded in — e.g. 'Maruti WagonR 2019, ~45,000 km,
              Delhi-NCR market'. Standard auto terms can stay English.>"
  },
  "jockeyPitch": {
    "headlineInr": <integer, MUST equal pricing.estimatedPriceInr exactly>,
    "script": "<ONE flowing paragraph (~5-8 sentences) the jockey reads
              out loud to the seller. Structure:
                (a) Open by stating the price (must be the exact same
                    integer as pricing.estimatedPriceInr — no other
                    number, no rounding to a different value).
                (a2) MARKET REFERENCE line — naturally cite that, as
                    per current market for this make/model/year/km,
                    similar cars typically sell in the range
                    \`marketReference.rangeLowInr\` to
                    \`marketReference.rangeHighInr\` (both in words),
                    so the offer is at / just below market — 'this
                    is the best price we can give for this car as
                    per the market today.'
                (b) Cite 2-4 concrete findings from the inspection
                    that justify why the offer isn't higher (faults,
                    paintwork, mileage, brake/engine issues, etc.).
                (c) Acknowledge the seller's likely pushback in one
                    polite line, then redirect to the data.
                (d) BRIDGE-TO-ASK SEGMENT — ONLY include this segment
                    when \`car.quotedPriceInr\` is non-null AND
                    pricing.estimatedPriceInr is below it. Naturally
                    work in: 'sir, if you want closer to / want to
                    match your asking price of <quoted in words>,
                    here's what would need fixing first — <name 2-3
                    specific repairable issues from the inspection,
                    e.g. brake pads, scratches, oil leak, check
                    engine light>. After those fixes we'd be able
                    to offer closer to your number.' Be specific,
                    not abstract — name the actual issues the
                    inspection turned up. If quoted price is null
                    or the offer already meets it, skip (d) entirely.
                (e) Close with a soft 'this is what we can offer
                    today' that leaves room for the seller to agree.
              Conversational, polite, persuasive. No bullet markers,
              no line breaks — one continuous paragraph the jockey
              can read straight through. Written in
              ${lang.name} using ${lang.script}.>"
  },
  "bridgeToAsk": <object OR null. Return null when \`car.quotedPriceInr\`
                  is null OR pricing.estimatedPriceInr already meets/
                  exceeds it. Otherwise:
    {
      "targetPriceInr": <integer, equal to car.quotedPriceInr — the
                         seller's ask we're trying to bridge to>,
      "issues": [
        // 2-4 SHORT, CONCRETE, REPAIRABLE items pulled from the
        // inspection that, if fixed, would meaningfully close the
        // gap to the seller's asking price. Each must reference a
        // real negative finding (faulty brakes, paint scratch,
        // engine warning, oil leak, tyre wear, etc.). Skip cosmetic
        // age-related items the seller can't fix (year of make,
        // km driven). Each item is one short phrase in
        // ${lang.name} using ${lang.script}. Include an approximate
        // INR fix cost in DIGITS at the end of each item, e.g.
        // "Front brake pads replace karwana (~₹4,000)" — the cost
        // helps the seller weigh effort vs. reward.
      ],
      "pitchLine": "<one polite sentence, ${lang.name} in ${lang.script},
                    that the jockey can read to the seller framing
                    the bridge — 'agar aap apni quoted price chahte
                    ho to ye thoda fix karwa lo, phir hum match kar
                    sakte hain'. Currency-in-words, no digits.>"
    }
  >,
  "nextSteps": {
    "instruction": "<one short paragraph (~2 sentences) for the
                   jockey explaining what to do RIGHT NOW. Cover:
                   (1) tap Play to listen to the script, then read
                       it out to the seller,
                   (2) if customer agrees, tap 'Customer agreed' —
                       it submits a lead and closes the deal,
                   (3) if customer disagrees, tap 'Customer not
                       agreed', ask their price, submit the ticket.
                   Written in ${lang.name} using ${lang.script}.>",
    "etiquetteTips": [
      // 2-3 short bullets reminding the jockey to be polite, listen
      // first, never argue, frame the lower price as protecting
      // both sides. Written in ${lang.name} using ${lang.script}.
    ]
  }
}

Rules:
1. estimatedPriceInr must fall inside [rangeLowInr, rangeHighInr] and
   should be at or slightly BELOW the midpoint — leave room to come
   up if the customer pushes. Never offer above the midpoint.
   QUOTED-PRICE ANCHOR (HARD):
     - If \`car.quotedPriceInr\` is non-null, \`estimatedPriceInr\` MUST
       be STRICTLY LESS THAN \`car.quotedPriceInr\`. There is no case
       where we offer more than the seller asked for.
     - The ONLY case where the offer may EQUAL the quoted price is
       when every inspection finding is clean / good AND the seller's
       quote is already inside [marketReference.rangeLowInr,
       marketReference.rangeHighInr]. Even then, prefer a token
       reduction (≥1%) so there is room to negotiate.
     - If \`quotedPriceInr\` is wildly above
       \`marketReference.rangeHighInr\` (e.g. ₹1 Cr quoted for a
       car whose typical market range is ₹5–6 L), the offer stays
       anchored to the inspection-adjusted fair value — do NOT
       inflate towards the unrealistic ask. The script's market
       reference line is the tool for this case.
     - Typical gap when condition is normal: 5–15% below the quote;
       wider when the inspection found real faults.
     - The script must explicitly acknowledge the seller's number
       before offering yours ("sir, you asked for X, but after the
       inspection we can do Y because…").
2. CRITICAL price consistency: the integer ANNOUNCED inside \`script\`
   MUST equal \`pricing.estimatedPriceInr\` exactly. If pricing says
   420000, the script must say "four lakh twenty thousand" / "चार लाख
   बीस हज़ार" / etc. — never a different rounded number. Do not
   restate the range inside the script; just the single offer.
3. If the inspection is incomplete or car attributes are sparse,
   lower confidence below 0.5 and widen the range. Don't refuse to
   price — give your best estimate.
4. ALL copy fields — \`factors\`, \`script\`, \`instruction\`,
   \`etiquetteTips\` — are written in ${lang.name} using ${lang.script}.
   No English-only bullets anywhere. Conversational, not formal.
   Standard auto terms (engine, brake, RC, km, etc.) can stay in
   English — that's how Indian sellers naturally hear them.
   CURRENCY-IN-WORDS (strict): inside \`script\` and any copy field
   that mentions the price, the amount MUST be spelled out fully in
   ${lang.name} currency words — NEVER as digits, NEVER mixed
   (no "₹4,20,000", no "420000", no "4.2 lakh" as a digit). Examples:
     - Hindi:   "चार लाख बीस हज़ार रुपये"
     - Telugu:  "నాలుగు లక్షల ఇరవై వేల రూపాయలు"
     - Bengali: "চার লাখ কুড়ি হাজার টাকা"
     - English: "four lakh twenty thousand rupees"
   The displayed price card already shows the digit form for visual
   reference — your job is the spoken/readable form using words only.
5. PRICE CONSISTENCY (re-stated for emphasis): before returning,
   verify that the amount your \`script\` reads aloud equals
   \`pricing.estimatedPriceInr\` exactly. If pricing says 420000
   and your draft script says "four lakh thirty thousand" or
   "साढ़े चार लाख", REWRITE the script with the correct number.
   The jockey will read the script while the screen shows the
   pricing number — any mismatch destroys their credibility.
6. The whole pitch is BUILT to defend a low offer. Issues come first,
   not last. If a finding was negative, name it. If a finding was
   neutral or mildly positive, only mention it when balancing a
   negative — don't hand the customer free ammunition.
7. Don't invent findings that aren't in the briefing. Reference real
   values (specific km, engine verdict, tyre count, etc.).
8. MARKET-REFERENCE rules:
   - \`marketReference.rangeLowInr\` and \`rangeHighInr\` describe a
     CONDITION-NEUTRAL market band for the make/model/year/fuel/km —
     they do NOT depend on this car's inspection findings (which
     pull \`pricing.estimatedPriceInr\` down).
   - In normal cases \`pricing.estimatedPriceInr\` should sit inside
     [marketReference.rangeLowInr, marketReference.rangeHighInr]; if
     the inspection found severe issues it may fall below.
   - The script's market-reference line is the jockey's response to
     seller anchoring (incl. absurd quotes like ₹1 Cr for a WagonR).
     Phrasing should be neutral and informational — "as per the
     current market for this car this is the typical range" — not
     judgemental about the seller's quote.
9. BRIDGE-TO-ASK rules:
   - Return \`bridgeToAsk: null\` whenever \`car.quotedPriceInr\` is null
     OR \`pricing.estimatedPriceInr >= car.quotedPriceInr\`. In those
     cases the script's (d) segment is also skipped.
   - Otherwise, \`bridgeToAsk.targetPriceInr\` MUST equal
     \`car.quotedPriceInr\` exactly.
   - \`bridgeToAsk.issues\` lists only REPAIRABLE problems found in the
     inspection — brake pads, paintwork scratches, tyre tread, oil
     leaks, dead battery, check-engine warnings, missing service
     records, broken trim, dirty interior, etc. Never include
     unfixable depreciation factors (year of make, km driven,
     ownership count). If the inspection didn't turn up enough
     repairable items, return at most what you have (1-2 items) —
     don't invent.
   - The bridge segment in \`script\` MUST name the same issues as
     \`bridgeToAsk.issues\` (1-to-1 wording can vary but the items
     must align), so the seller hears the same list the jockey sees
     on screen.
10. Keep money phrasing natural for ${lang.name} speakers — use lakh /
   hazaar (or the language's equivalent) rather than "INR 420000".`;

  const res = await fetch(OPENAI_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: PRICING_MODEL,
      response_format: { type: 'json_object' },
      messages: [{ role: 'user', content: prompt }],
    }),
  });
  const raw = await res.text();
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${raw.slice(0, 200)}`);
  const json = JSON.parse(raw);
  const content = json.choices?.[0]?.message?.content;
  if (!content) throw new Error('Empty content from OpenAI');
  return JSON.parse(content);
}

/// Same numeric coercion used in createInspection — accept a raw int
/// OR a numeric string, reject NaN / floats / non-numeric strings.
function intOrNull(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isFinite(n) || !Number.isInteger(n)) return null;
  return n;
}
