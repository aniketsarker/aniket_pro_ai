const { getStore, connectLambda } = require('@netlify/blobs');

const UID_RE = /^[A-Za-z0-9_-]{8,64}$/;

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method not allowed' };
  }
  try {
    connectLambda(event);
    const store = getStore('aniket-alerts');
    if (!event.body || event.body.length > 20000) {
      return { statusCode: 400, body: 'Bad body' };
    }
    const body = JSON.parse(event.body);
    const uid = body.uid;
    const sub = body.sub;
    if (!uid || !UID_RE.test(uid)) {
      return { statusCode: 400, body: 'Invalid uid' };
    }
    if (!sub || typeof sub.endpoint !== 'string' || sub.endpoint.indexOf('https://') !== 0 || !sub.keys) {
      return { statusCode: 400, body: 'Invalid subscription' };
    }
    await store.setJSON('sub-' + uid, { endpoint: sub.endpoint, keys: sub.keys });
    return { statusCode: 200, body: JSON.stringify({ ok: true }) };
  } catch (e) {
    return { statusCode: 500, body: JSON.stringify({ error: e.message }) };
  }
};
