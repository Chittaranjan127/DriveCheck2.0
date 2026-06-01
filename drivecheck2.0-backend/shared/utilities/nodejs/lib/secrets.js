const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const client = new SecretsManagerClient({});
const cache = new Map();

/**
 * Fetch and cache a JSON secret. Subsequent calls within the same warm
 * Lambda container return the cached value (no network).
 */
async function getJsonSecret(arn) {
  if (cache.has(arn)) return cache.get(arn);
  const res = await client.send(new GetSecretValueCommand({ SecretId: arn }));
  const parsed = JSON.parse(res.SecretString);
  cache.set(arn, parsed);
  return parsed;
}

module.exports = { getJsonSecret };
