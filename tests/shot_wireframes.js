// Render each catch-entry wireframe at an iPhone 390x844 viewport, measure whether
// it overflows (the hard "no scroll / no clip" constraint), and screenshot it.
// Then assemble a labeled contact sheet of all of them.
// Usage: node tests/shot_wireframes.js
const puppeteer = require('puppeteer-core');
const fs = require('fs');
const path = require('path');

const EXE = [
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
].find(p => { try { return fs.existsSync(p); } catch { return false; } });

const SLUGS = ['radial-dial','tile-dashboard','voice-first','swipe-deck','summary-confirm',
  'ruler-hero','drum-wheels','map-sheet','chip-board','watch-compact'];
const WF = path.resolve('wireframes/claude');
const SHOTS = path.join(WF, 'shots');
fs.mkdirSync(SHOTS, { recursive: true });

(async () => {
  const browser = await puppeteer.launch({ executablePath: EXE, headless: 'new',
    args: ['--no-sandbox','--disable-dev-shm-usage','--allow-file-access-from-files','--hide-scrollbars'] });
  const results = [];
  for (const slug of SLUGS) {
    const file = path.join(WF, slug + '.html');
    if (!fs.existsSync(file)) { results.push({ slug, missing: true }); continue; }
    const page = await browser.newPage();
    await page.setViewport({ width: 1100, height: 1100, deviceScaleFactor: 2 });
    const errs = [];
    page.on('pageerror', e => errs.push(e.message));
    await page.goto('file://' + file, { waitUntil: 'networkidle0', timeout: 30000 });
    await new Promise(r => setTimeout(r, 600));
    // Find the iPhone-screen element (sized ~390x844) and measure ITS content overflow.
    const m = await page.evaluate(() => {
      let best = null;
      for (const el of document.querySelectorAll('*')) {
        const r = el.getBoundingClientRect();
        if (r.width >= 358 && r.width <= 400 && r.height >= 795 && r.height <= 860) {
          if (!best || r.height > best.h) best = { el, w: r.width, h: r.height, x: r.left, y: r.top,
            overflow: el.scrollHeight - el.clientHeight };
        }
      }
      if (!best) { const d = document.documentElement; return { found: false, sh: d.scrollHeight }; }
      return { found: true, w: Math.round(best.w), h: Math.round(best.h),
        x: best.x, y: best.y, overflow: best.overflow };
    });
    if (m.found) {
      const pad = 1;
      await page.screenshot({ path: path.join(SHOTS, slug + '.png'),
        clip: { x: Math.max(0, m.x - pad), y: Math.max(0, m.y - pad), width: m.w + pad * 2, height: m.h + pad * 2 } });
    } else {
      await page.screenshot({ path: path.join(SHOTS, slug + '.png') });
    }
    results.push({ slug, frame: m.found ? `${m.w}x${m.h}` : 'NOT-FOUND',
      contentOverflow: m.found ? m.overflow : null, ok: m.found && m.overflow <= 1, errs: errs.slice(0, 2) });
    await page.close();
  }

  // contact sheet: 5 cols x 2 rows of the captured PNGs, labeled
  const cells = SLUGS.map((s, i) => {
    const r = results[i] || {};
    const badge = r.missing ? 'MISSING' : (r.ok ? 'fits' : `+${Math.max(r.vOver,0)}h/${Math.max(r.hOver,0)}w`);
    const col = r.missing ? '#e0554e' : (r.ok ? '#20d39b' : '#ffd45a');
    return `<figure><img src="shots/${s}.png"><figcaption><b>${i+1}. ${s}</b>` +
      `<span style="color:${col}">&nbsp;${badge}</span></figcaption></figure>`;
  }).join('');
  const sheet = `<!doctype html><meta charset=utf-8><style>
    body{margin:0;background:#0b1118;font-family:-apple-system,Arial,sans-serif;padding:22px}
    .grid{display:grid;grid-template-columns:repeat(5,1fr);gap:18px}
    figure{margin:0}img{width:100%;display:block;border-radius:14px;border:1px solid #223}
    figcaption{color:#cdd;font-size:15px;margin-top:8px}
  </style><div class=grid>${cells}</div>`;
  const sheetPath = path.join(WF, 'contact-sheet.html');
  fs.writeFileSync(sheetPath, sheet);
  const page = await browser.newPage();
  await page.setViewport({ width: 1860, height: 900, deviceScaleFactor: 1 });
  await page.goto('file://' + sheetPath, { waitUntil: 'networkidle0' });
  await new Promise(r => setTimeout(r, 800));
  await page.screenshot({ path: '/tmp/wireframes-contact.png', fullPage: true });

  console.log(JSON.stringify(results, null, 1));
  await browser.close();
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
