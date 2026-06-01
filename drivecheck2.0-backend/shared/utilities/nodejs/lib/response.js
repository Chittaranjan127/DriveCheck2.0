const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,x-api-key',
  'Content-Type': 'application/json',
};

const json = (statusCode, body) => ({
  statusCode,
  headers: CORS,
  body: JSON.stringify(body),
});

module.exports = {
  ok: (data) => json(200, { ok: true, data }),
  created: (data) => json(201, { ok: true, data }),
  badRequest: (message, details) => json(400, { ok: false, error: { code: 'BAD_REQUEST', message, details } }),
  unauthorized: (message = 'Unauthorized') => json(401, { ok: false, error: { code: 'UNAUTHORIZED', message } }),
  notFound: (message = 'Not found') => json(404, { ok: false, error: { code: 'NOT_FOUND', message } }),
  serverError: (err) => {
    console.error('SERVER_ERROR', err);
    return json(500, { ok: false, error: { code: 'SERVER_ERROR', message: err?.message ?? 'Server error' } });
  },
};
