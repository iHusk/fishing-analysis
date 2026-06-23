// Headless screenshot of the Trip Wrapped poster with Map: On — so we can verify
// the satellite compositing renders correctly (the harness can't reach this overlay).
// Usage: node tests/shot_wrapped.js <replay.html> [out.png]
const puppeteer = require('puppeteer-core');
const fs = require('fs');

const CANDIDATES = [
  process.env.CHROME,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
].filter(Boolean);
const exe = CANDIDATES.find(p => { try { return fs.existsSync(p); } catch (_) { return false; } });

(async () => {
  const file = process.argv[2];
  const out = process.argv[3] || '/tmp/wrapped.png';
  if (!exe) { console.error('no Chrome found'); process.exit(2); }
  const browser = await puppeteer.launch({ executablePath: exe, headless: 'new', args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 1750, deviceScaleFactor: 1 });
  const errs = [];
  page.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  page.on('pageerror', e => errs.push('PAGEERR ' + e.message));
  await page.goto('file://' + file, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await new Promise(r => setTimeout(r, 1500));
  const present = await page.evaluate(() => ['#btnWrap', '#ecWrap', '#wrapOverlay', '#wrapImg', '#wrapMap'].map(s => s + ':' + !!document.querySelector(s)));
  // open Wrapped via in-page click (bypasses actionability), then turn Map On
  await page.evaluate(() => { const b = document.querySelector('#btnWrap'); if (b) b.click(); });
  await new Promise(r => setTimeout(r, 1500));
  const afterOpen = await page.evaluate(() => { const im = document.querySelector('#wrapImg'); const ov = document.querySelector('#wrapOverlay'); return { ovClass: ov && ov.className, src: im && im.src.slice(0, 18), nw: im && im.naturalWidth }; });
  await page.evaluate(() => { const m = document.querySelector('#wrapMap'); if (m) m.click(); });
  await new Promise(r => setTimeout(r, 18000)); // tiles fetch + composite (headless is slow)
  const info = await page.evaluate(() => { const im = document.querySelector('#wrapImg'); return { nw: im && im.naturalWidth, nh: im && im.naturalHeight, src: im && im.src.slice(0, 18) }; });
  await page.screenshot({ path: out });        // full viewport (the modal covers it)
  console.log('saved', out);
  console.log('present:', JSON.stringify(present));
  console.log('afterOpen:', JSON.stringify(afterOpen));
  console.log('afterMapOn:', JSON.stringify(info), '| console errors:', errs.slice(0, 6));
  await browser.close();
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
