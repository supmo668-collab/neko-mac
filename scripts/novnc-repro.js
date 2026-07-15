// Instrumented KasmVNC/noVNC connection repro — captures every client-side failure so a
// "noVNC encountered an error" can be diagnosed systematically instead of by inference.
//
// It opens the KasmVNC web client, drives the desktop for ~90 s (mouse/scroll/click to
// generate encode load), and logs: console errors/warnings, pageerror stacks, websocket
// open/close/error, failed requests (incl. TLS cert errors), and the on-screen noVNC
// status banner. A final screenshot is written next to the log.
//
// The key finding this tool produced: over http -> ws it is flawless; over https the
// self-signed cert throws net::ERR_CERT_AUTHORITY_INVALID on the wss channel. Fix = give
// the cert a matching SAN and trust it on the Mac (see docs/VM-VARIANTS.md).
//
// Requires: `npm i -g playwright` (or a local install) + system Google Chrome (uses
// channel:'chrome' to avoid a browser download / version mismatch).
//
// Usage:
//   KASM_USER=collab KASM_PASS=... node scripts/novnc-repro.js <out.log> <url>
//   e.g. node scripts/novnc-repro.js /tmp/novnc.log http://127.0.0.1:6080/
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs');

const OUT = process.argv[2] || '/tmp/novnc-capture.log';
const URL = process.argv[3] || 'http://127.0.0.1:6080/';
const log = (tag, msg) => {
  const line = `${new Date().toISOString()} [${tag}] ${msg}`;
  fs.appendFileSync(OUT, line + '\n');
  console.log(line);
};

(async () => {
  fs.writeFileSync(OUT, '');
  // Anti-throttling flags are ESSENTIAL for a stable KasmVNC transport when Claude/an agent
  // drives in headless/debug mode: Chrome treats a headless or backgrounded tab as hidden and
  // throttles its timers + backgrounds the renderer, which lapses the noVNC websocket heartbeat
  // and drops the connection every few minutes. These keep the tab "foreground/awake" so the
  // socket stays alive. Same flags belong on ANY browser/agent driving this desktop.
  const STABILITY_ARGS = (process.env.CHROME_ARGS ? process.env.CHROME_ARGS.split(' ') : []).concat([
    '--disable-background-timer-throttling',
    '--disable-backgrounding-occluded-windows',
    '--disable-renderer-backgrounding',
    '--disable-features=CalculateNativeWinOcclusion,IntensiveWakeUpThrottling',
    '--disable-ipc-flooding-protection',
  ]);
  const browser = await chromium.launch({ headless: true, channel: 'chrome', args: STABILITY_ARGS });
  const ctx = await browser.newContext({
    httpCredentials: { username: process.env.KASM_USER || 'collab', password: process.env.KASM_PASS || '' },
    ignoreHTTPSErrors: false, // we WANT to surface cert failures, not mask them
  });
  const page = await ctx.newPage();

  page.on('console', m => { if (['error', 'warning'].includes(m.type())) log('console.' + m.type(), m.text()); });
  page.on('pageerror', e => log('PAGEERROR', (e.stack || e.message || String(e)).slice(0, 2000)));
  page.on('requestfailed', r => log('REQFAIL', `${r.url()} :: ${r.failure() && r.failure().errorText}`));
  page.on('websocket', ws => {
    log('WS.open', ws.url());
    ws.on('close', () => log('WS.close', ws.url()));
    ws.on('socketerror', err => log('WS.error', `${ws.url()} :: ${err}`));
  });

  const dumpBanners = async (when) => {
    const texts = await page.evaluate(() => {
      const sels = ['#noVNC_status', '.noVNC_status', '#noVNC_fallback_error', '.notification', '[class*="error"]'];
      const out = [];
      for (const s of sels) document.querySelectorAll(s).forEach(el => {
        const t = (el.innerText || '').trim();
        if (t) out.push(`${s} :: ${t.slice(0, 300)}`);
      });
      return out;
    }).catch(e => ['evaluate failed: ' + e.message]);
    texts.forEach(t => log('BANNER@' + when, t));
  };

  log('nav', 'goto ' + URL);
  await page.goto(URL, { waitUntil: 'load', timeout: 30000 });
  await page.waitForTimeout(4000);
  await dumpBanners('after-load');

  log('drive', 'starting 90s interaction loop');
  const box = await page.evaluate(() => ({ w: window.innerWidth, h: window.innerHeight }));
  for (let i = 0; i < 45; i++) {
    const x = 100 + Math.floor((i * 37) % (box.w - 200));
    const y = 100 + Math.floor((i * 53) % (box.h - 200));
    await page.mouse.move(x, y, { steps: 10 });
    if (i % 5 === 0) await page.mouse.wheel(0, 300);
    if (i % 7 === 0) await page.mouse.click(x, y);
    await page.waitForTimeout(2000);
    if (i % 10 === 9) await dumpBanners('t+' + (i * 2) + 's');
  }
  await dumpBanners('end');
  await page.screenshot({ path: OUT.replace(/\.log$/, '') + '-final.png' });
  log('done', 'capture complete');
  await browser.close();
})().catch(e => { log('FATAL', e.stack || String(e)); process.exit(1); });
