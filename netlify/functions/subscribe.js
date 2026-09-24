const { getStore } = require('@netlify/blobs');

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method not allowed' };
  }
  try {
    const store = getStore('aniket-alerts');
    const sub = JSON.parse(event.body || '{}');
    if (!sub || !sub.endpoint) {
      return { statusCode: 400, body: 'Invalid subscription' };
    }
    await store.setJSON('subscription', sub);
    return { statusCode: 200, body: JSON.stringify({ ok: true }) };
  } catch (e) {
    return { statusCode: 500, body: JSON.stringify({ error: e.message }) };
  }
};
