// Private database transport for the Railway API. Never expose this token to apps.
export default {
  async fetch(request, env) {
    if (
      !env.DONY_D1_TOKEN ||
      request.headers.get('Authorization') !== `Bearer ${env.DONY_D1_TOKEN}`
    )
      return new Response('Unauthorized', { status: 401 });
    if (request.method !== 'POST' || new URL(request.url).pathname !== '/query')
      return new Response('Not found', { status: 404 });
    try {
      const { batch } = await request.json();
      if (
        !Array.isArray(batch) ||
        !batch.length ||
        batch.some(
          (item) =>
            typeof item.sql !== 'string' ||
            (item.params !== undefined && !Array.isArray(item.params))
        )
      )
        return new Response('Invalid batch', { status: 400 });
      // Always read the primary: revision checks must never use a stale replica.
      const database = env.DB.withSession('first-primary');
      const result = await database.batch(
        batch.map(({ sql, params = [] }) =>
          database.prepare(sql).bind(...params)
        )
      );
      return Response.json(
        { success: true, result },
        { headers: { 'Cache-Control': 'no-store' } }
      );
    } catch (error) {
      const conflict =
        error instanceof Error &&
        error.message.includes('dony_transaction_conflict');
      return Response.json(
        {
          success: false,
          errors: [
            {
              message: conflict
                ? 'dony_transaction_conflict'
                : 'D1 query failed.'
            }
          ]
        },
        { status: conflict ? 409 : 500 }
      );
    }
  }
};
