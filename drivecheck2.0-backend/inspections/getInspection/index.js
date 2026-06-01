const { GetCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb } = require('/opt/nodejs/lib/dynamo');
const { ok, notFound, badRequest, serverError } = require('/opt/nodejs/lib/response');

const TABLE = process.env.INSPECTIONS_TABLE;

exports.handler = async (event) => {
  try {
    const id = event.pathParameters?.id;
    if (!id) return badRequest('Missing path param: id');

    const res = await ddb.send(new GetCommand({ TableName: TABLE, Key: { id } }));
    if (!res.Item) return notFound(`Inspection ${id} not found`);
    return ok(res.Item);
  } catch (err) {
    return serverError(err);
  }
};
