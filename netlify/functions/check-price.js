const { getStore } = require('@netlify/blobs');
const webpush = require('web-push');

const TV = {
  XAU: { kind: 'gold' },
  BTC: { kind: 'binance', pair: 'BTCUSDT' },
  ETH: { kind: 'binance', pair: 'ETHUSDT' },
  US30: { kind: 'twelvedata', symbol: 'DJI' }
};

async function fetchPrice(symbol) {
  const cfg = TV[symbol];
  if (!cfg) return null;
  try {
    if (cfg.kind === 'gold') {
      const r = await fetch('https://api.gold-api.com/price/XAU');
      const j = await r.json();
      if (j && j.price) return Number(j.price);
    } else if (cfg.kind === 'binance') {
      const r = await fetch('https://api.binance.com/api/v3/ticker/price?symbol=' + cfg.pair);
      const j = await r.json();
      if (j && j.price) return Number(j.price);
    } else if (cfg.kind === 'twelvedata' && process.env.TWELVE_DATA_KEY) {
      const r = await fetch('https://api.twelvedata.com/price?symbol=' + cfg.symbol + '&apikey=' + process.env.TWELVE_DATA_KEY);
      const j = await r.json();
      if (j && j.price) return Number(j.price);
    }
  } catch (e) {}
  return null;
}

exports.handler = async () => {
  try {
    const store = getStore('aniket-alerts');
    const plan = await store.get('waitplan', { type: 'json' });
    const sub = await store.get('subscription', { type: 'json' });

    if (!plan || !sub || !plan.plans || !plan.plans.length) {
      return { statusCode: 200, body: 'nothing to check' };
    }
    if (Date.now() - (plan.ts || 0) > 3 * 3600000) {
      await store.setJSON('waitplan', { plans: [], notified: [] });
      return { statusCode: 200, body: 'expired' };
    }

    const price = await fetchPrice(plan.symbol);
    if (!price) return { statusCode: 200, body: 'no price' };

    webpush.setVapidDetails(
      'mailto:aniket@example.com',
      process.env.VAPID_PUBLIC_KEY,
      process.env.VAPID_PRIVATE_KEY
    );

    const tol = plan.tolerance || 50;
    const notified = plan.notified || [];
    let changed = false;

    for (let i = 0; i < plan.plans.length; i++) {
      if (notified.indexOf(i) !== -1) continue;
      const w = plan.plans[i];
      const lvl = parseFloat(w.if_price);
      if (isNaN(lvl)) continue;
      if (Math.abs(price - lvl) <= tol) {
        const payload = JSON.stringify({
          title: '🔔 Wait Plan Ready! (' + plan.symbol + ')',
          body: (w.direction || '') + ' setup — price ' + price + ' level ' + lvl + '. SL ' + (w.sl || '?') + ' | TP ' + (w.tp || '?'),
          url: '/'
        });
        try { await webpush.sendNotification(sub, payload); } catch (e) {}
        notified.push(i);
        changed = true;
      }
    }

    if (changed) {
      plan.notified = notified;
      await store.setJSON('waitplan', plan);
    }

    return { statusCode: 200, body: JSON.stringify({ price, notified }) };
  } catch (e) {
    return { statusCode: 500, body: JSON.stringify({ error: e.message }) };
  }
};
