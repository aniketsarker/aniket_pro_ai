const { getStore, connectLambda } = require('@netlify/blobs');

const UID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const SYMBOLS = ['XAU', 'BTC', 'ETH', 'US30'];

function clip(v, n) {
  return String(v == null ? '' : v).slice(0, n);
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method not allowed' };
  }
  try {
    connectLambda(event);
    const store = getStore('aniket-alerts');
    if (!event.body || event.body.length > 50000) {
      return { statusCode: 400, body: 'Bad body' };
    }
    const payload = JSON.parse(event.body);
    const uid = payload.uid;
    if (!uid || !UID_RE.test(uid)) {
      return { statusCode: 400, body: 'Invalid uid' };
    }
    if (SYMBOLS.indexOf(payload.symbol) === -1) {
      return { statusCode: 400, body: 'Invalid symbol' };
    }
    if (!Array.isArray(payload.plans)) {
      return { statusCode: 400, body: 'Invalid plans' };
    }
    let tol = Number(payload.tolerance);
    if (!isFinite(tol) || tol <= 0 || tol > 5000) tol = 50;

    const plans = payload.plans.slice(0, 5).map((w) => ({
      direction: clip(w && w.direction, 12),
      if_price: clip(w && w.if_price, 60),
      trigger: clip(w && w.trigger, 200),
      sl: clip(w && w.sl, 40),
      tp: clip(w && w.tp, 40)
    }));

    await store.setJSON('plan-' + uid, {
      symbol: payload.symbol,
      tolerance: tol,
      ts: Date.now(),
      plans: plans,
      notified: [],
      lastPrice: null
    });
    return { statusCode: 200, body: JSON.stringify({ ok: true }) };
  } catch (e) {
    return { statusCode: 500, body: JSON.stringify({ error: e.message }) };
  }
};
