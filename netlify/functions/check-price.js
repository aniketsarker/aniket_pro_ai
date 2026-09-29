const { getStore, connectLambda } = require('@netlify/blobs');
const webpush = require('web-push');

const MAX_AGE_MS = 3 * 3600000;

function numFrom(v) {
  const m = String(v == null ? '' : v).replace(/,/g, '').match(/\d+(?:\.\d+)?/g);
  if (!m || !m.length) return NaN;
  const a = parseFloat(m[0]);
  if (m.length >= 2) {
    const b = parseFloat(m[1]);
    if (isFinite(b)) return (a + b) / 2;
  }
  return a;
}

async function getJson(url) {
  const r = await fetch(url);
  return r.json();
}

async function fetchPrice(symbol) {
  try {
    if (symbol === 'XAU') {
      try {
        const j = await getJson('https://api.gold-api.com/price/XAU');
        if (j && Number(j.price) > 0) return Number(j.price);
      } catch (e) {}
      const p = await getJson('https://api.binance.com/api/v3/ticker/price?symbol=PAXGUSDT');
      if (p && Number(p.price) > 0) return Number(p.price);
    } else if (symbol === 'BTC' || symbol === 'ETH') {
      const j = await getJson('https://api.binance.com/api/v3/ticker/price?symbol=' + symbol + 'USDT');
      if (j && Number(j.price) > 0) return Number(j.price);
    } else if (symbol === 'US30' && process.env.TWELVE_DATA_KEY) {
      const keys = String(process.env.TWELVE_DATA_KEY).split(/[\s,;]+/).filter(Boolean);
      const key = keys[Math.floor(Math.random() * keys.length)];
      const names = ['US30/USD', 'DJI'];
      for (const n of names) {
        const j = await getJson('https://api.twelvedata.com/price?symbol=' + encodeURIComponent(n) + '&apikey=' + key);
        if (j && Number(j.price) > 0) return Number(j.price);
      }
    }
  } catch (e) {}
  return null;
}

exports.handler = async (event) => {
  try {
    connectLambda(event);
    const store = getStore('aniket-alerts');
    const listing = await store.list({ prefix: 'plan-' });
    const blobs = (listing && listing.blobs) || [];
    if (!blobs.length) {
      return { statusCode: 200, body: JSON.stringify({ users: 0, sent: 0 }) };
    }

    webpush.setVapidDetails(
      'mailto:aniket@example.com',
      process.env.VAPID_PUBLIC_KEY,
      process.env.VAPID_PRIVATE_KEY
    );

    const priceCache = {};
    let sent = 0;

    for (const b of blobs) {
      const uid = b.key.slice('plan-'.length);
      const plan = await store.get(b.key, { type: 'json' });
      if (!plan || !Array.isArray(plan.plans) || !plan.plans.length || Date.now() - (plan.ts || 0) > MAX_AGE_MS) {
        await store.delete(b.key);
        continue;
      }
      const sub = await store.get('sub-' + uid, { type: 'json' });
      if (!sub) continue;

      if (!(plan.symbol in priceCache)) {
        priceCache[plan.symbol] = await fetchPrice(plan.symbol);
      }
      const price = priceCache[plan.symbol];
      if (!price) continue;

      const near = (plan.tolerance || 50) * 0.2;
      const notified = plan.notified || [];
      const last = typeof plan.lastPrice === 'number' ? plan.lastPrice : null;

      for (let i = 0; i < plan.plans.length; i++) {
        if (notified.indexOf(i) !== -1) continue;
        const w = plan.plans[i];
        const lvl = numFrom(w.if_price);
        if (!isFinite(lvl)) continue;
        const crossed = last !== null && (last - lvl) * (price - lvl) < 0;
        if (Math.abs(price - lvl) <= near || crossed) {
          const payload = JSON.stringify({
            title: '🔔 Wait Plan Ready! (' + plan.symbol + ')',
            body: (w.direction || '') + ' setup — price ' + price + ', level ' + lvl + ' e pouchechhe. SL ' + (w.sl || '?') + ' | TP ' + (w.tp || '?'),
            tag: 'wp-' + plan.symbol + '-' + i,
            url: '/'
          });
          try {
            await webpush.sendNotification(sub, payload);
            sent++;
          } catch (e) {
            if (e && (e.statusCode === 404 || e.statusCode === 410)) {
              await store.delete('sub-' + uid);
            }
          }
          notified.push(i);
        }
      }

      plan.notified = notified;
      plan.lastPrice = price;
      await store.setJSON(b.key, plan);
    }

    return { statusCode: 200, body: JSON.stringify({ users: blobs.length, sent: sent }) };
  } catch (e) {
    return { statusCode: 500, body: JSON.stringify({ error: e.message }) };
  }
};
