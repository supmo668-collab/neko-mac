// Detect "blank to white after each frame" by sampling the noVNC canvas over time.
const { chromium } = require('/Users/mo/.npm/_npx/9833c18b2d85bc59/node_modules/playwright');
const fs = require('fs');
const OUT = process.argv[2] || '/tmp/flicker.log';
const URL = process.argv[3] || 'http://127.0.0.1:6080/';
const log = (t, m) => { const l = `${new Date().toISOString()} [${t}] ${m}`; fs.appendFileSync(OUT, l + '\n'); console.log(l); };

(async () => {
  fs.writeFileSync(OUT, '');
  const extraArgs = (process.env.CHROME_ARGS || '').split(' ').filter(Boolean);
  const browser = await chromium.launch({ headless: true, channel: 'chrome', args: extraArgs });
  const ctx = await browser.newContext({ httpCredentials: { username: process.env.KASM_USER || 'collab', password: process.env.KASM_PASS || '' }, ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => log('PAGEERROR', (e.message || String(e)).slice(0, 200)));
  if (process.env.THROTTLE_KBPS) {
    const cdp = await page.context().newCDPSession(page);
    const bps = parseInt(process.env.THROTTLE_KBPS) * 1024 / 8;
    await cdp.send('Network.emulateNetworkConditions', { offline: false, downloadThroughput: bps, uploadThroughput: bps, latency: 80 });
    log('throttle', process.env.THROTTLE_KBPS + ' kbps, 80ms latency (simulated tailnet hop)');
  }

  await page.goto(URL, { waitUntil: 'load', timeout: 30000 });
  await page.waitForTimeout(4000);

  // sample the largest canvas' white fraction every 400ms while interacting
  const sample = () => page.evaluate(() => {
    const cs = [...document.querySelectorAll('canvas')].sort((a, b) => b.width * b.height - a.width * a.height);
    const c = cs[0];
    if (!c || !c.width) return { err: 'no-canvas' };
    try {
      const g = c.getContext('2d', { willReadFrequently: true });
      if (!g) return { err: 'no-2d-ctx', w: c.width, h: c.height };
      const d = g.getImageData(0, 0, c.width, c.height).data;
      let white = 0, n = 0;
      for (let i = 0; i < d.length; i += 4 * 97) { n++; if (d[i] > 245 && d[i + 1] > 245 && d[i + 2] > 245) white++; }
      return { w: c.width, h: c.height, whitePct: Math.round((white / n) * 100) };
    } catch (e) { return { err: 'readback:' + e.message.slice(0, 60), w: c.width, h: c.height }; }
  }).catch(e => ({ err: 'eval:' + e.message.slice(0, 60) }));

  const box = await page.evaluate(() => ({ w: window.innerWidth, h: window.innerHeight }));
  log('start', 'sampling canvas every 400ms for ~40s while interacting');
  const marks = [];
  for (let i = 0; i < 100; i++) {
    if (i % 6 === 0) { await page.mouse.move(120 + (i * 31) % (box.w - 240), 120 + (i * 47) % (box.h - 240), { steps: 6 }); await page.mouse.wheel(0, i % 2 ? 500 : -500); }
    if (i % 15 === 0) await page.mouse.click(200 + (i % 400), 200 + (i % 200));
    const s = await sample();
    marks.push(s.whitePct);
    if (i % 5 === 0 || s.err) log('sample', JSON.stringify(s));
    await page.waitForTimeout(400);
  }
  const vals = marks.filter(v => typeof v === 'number');
  if (vals.length) {
    const mn = Math.min(...vals), mx = Math.max(...vals), avg = Math.round(vals.reduce((a, b) => a + b, 0) / vals.length);
    const blanks = vals.filter(v => v > 97).length;
    log('SUMMARY', `whitePct min=${mn} max=${mx} avg=${avg}; near-fully-white frames(>97%)=${blanks}/${vals.length}  => ${blanks > 2 ? 'FLICKER/BLANKING DETECTED' : 'no blanking'}`);
  }
  await browser.close();
})().catch(e => { log('FATAL', e.stack || String(e)); process.exit(1); });
