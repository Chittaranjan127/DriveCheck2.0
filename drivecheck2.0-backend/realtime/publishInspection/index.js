const aws4 = require('aws4');

/**
 * DynamoDB stream → AppSync mutation publisher.
 *
 * Triggered on every INSERT / MODIFY in `DriveCheck-Inspections-{Stage}`.
 * Translates each row into the AppSync `publishInspectionChanged`
 * mutation; subscribed clients (Flutter home page) receive the
 * resulting payload over the AppSync real-time WebSocket.
 *
 * Auth: SigV4 (via the `aws4` package — tiny single-file signer) against
 * the AppSync HTTP endpoint. The Lambda's execution role has
 * `appsync:GraphQL` on the specific mutation field, so signed requests
 * bypass the API_KEY auth used by clients.
 *
 * Soft-fail: per-record errors are logged but don't fail the whole
 * batch — the stream would retry and we'd republish duplicates,
 * which is fine for an idempotent "current state" subscription.
 *
 * Bundled deps kept minimal — Lambda's Node.js 20 runtime already
 * ships the AWS SDK v3, and `aws4` is a single ~30 KB file with no
 * transitive dependencies.
 */

const APPSYNC_URL = process.env.APPSYNC_GRAPHQL_URL;
const REGION = process.env.AWS_REGION || 'ap-south-1';

exports.handler = async (event) => {
  const records = event.Records ?? [];
  if (records.length === 0) return { handled: 0 };

  let handled = 0;
  for (const r of records) {
    if (r.eventName !== 'INSERT' && r.eventName !== 'MODIFY') continue;
    const image = r.dynamodb?.NewImage;
    if (!image) continue;

    const row = unmarshall(image);
    if (!row.id) continue;

    try {
      await publish(row);
      handled += 1;
    } catch (err) {
      console.error('publish_failed', { id: row.id, err: err.message });
    }
  }
  return { handled };
};

async function publish(row) {
  const body = JSON.stringify({
    query: `mutation P($i: InspectionInput!) {
      publishInspectionChanged(input: $i) {
        id assignedTo status completedStepCount stepCount
        carTitle customerName scheduledAt updatedAt
      }
    }`,
    variables: {
      i: {
        id: row.id,
        assignedTo: row.assignedTo,
        status: row.status,
        completedStepCount: numberOrNull(row.completedStepCount),
        stepCount: numberOrNull(row.stepCount),
        carTitle: stringOrNull(row.carTitle),
        customerName: stringOrNull(row.customerName),
        scheduledAt: stringOrNull(row.scheduledAt),
        updatedAt: stringOrNull(row.updatedAt),
      },
    },
  });

  const url = new URL(APPSYNC_URL);
  // aws4.sign mutates the passed-in object and returns it with the
  // SigV4 `Authorization` + `X-Amz-Date` (+ `X-Amz-Security-Token` for
  // temp creds) headers populated. Credentials come from the Lambda
  // execution role via the standard env vars the runtime injects.
  const signed = aws4.sign(
    {
      host: url.hostname,
      path: url.pathname,
      method: 'POST',
      service: 'appsync',
      region: REGION,
      headers: { 'Content-Type': 'application/json' },
      body,
    },
    {
      accessKeyId: process.env.AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      sessionToken: process.env.AWS_SESSION_TOKEN,
    },
  );

  const res = await fetch(APPSYNC_URL, {
    method: 'POST',
    headers: signed.headers,
    body,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`AppSync ${res.status}: ${text.slice(0, 200)}`);
  }
  const json = await res.json();
  if (json.errors) {
    throw new Error(`AppSync GraphQL: ${JSON.stringify(json.errors)}`);
  }
}

/**
 * Hand-rolled DynamoDB AttributeValue → plain-JS unmarshaller for
 * the subset of types our Inspections rows actually use. Avoids
 * pulling in `@aws-sdk/util-dynamodb` — the cases below cover S
 * (string), N (number), BOOL, NULL, L (list), and M (nested map).
 */
function unmarshall(image) {
  const out = {};
  for (const [k, v] of Object.entries(image)) {
    out[k] = decodeValue(v);
  }
  return out;
}

function decodeValue(av) {
  if (av == null) return null;
  if ('S' in av) return av.S;
  if ('N' in av) {
    const n = Number(av.N);
    return Number.isFinite(n) ? n : av.N;
  }
  if ('BOOL' in av) return av.BOOL;
  if ('NULL' in av) return null;
  if ('L' in av) return av.L.map(decodeValue);
  if ('M' in av) return unmarshall(av.M);
  // Skip B (binary), SS/NS/BS (string/number/binary sets) — not used
  // by our rows. Returning null avoids crashing on unexpected types.
  return null;
}

function stringOrNull(v) {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

function numberOrNull(v) {
  if (typeof v === 'number') return v;
  if (typeof v === 'string' && v !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}
