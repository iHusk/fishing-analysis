/* Replay-map performance benchmark (real headless Chrome).
 *
 * Loads a generated replay HTML, plays it at a fixed speed, and measures:
 *   - per-frame intervals (FPS, p50/p95/p99, worst frame, % frames over 16.7ms / 33ms)
 *   - Chrome main-thread counters during playback: Layout count, Style recalcs, JS heap
 * Tile servers are blocked (request interception) so runs are deterministic + network-light;
 * the Leaflet/leaflet.heat CDN is allowed.
 *
 * Usage:
 *   node tests/bench.js <generated.html> [speedMultiplier=800] [measureSeconds=12]
 *   node tests/bench.js <html> --json            # machine-readable line for tracking
 *
 * Needs puppeteer-core + a local Chrome (auto-detected). Compare the SAME file before/after a
 * change: lower frame times + fewer Layout/Recalc per frame = faster.
 */
const fs = require("fs");
const path = require("path");

let puppeteer;
try { puppeteer = require("puppeteer-core"); }
catch { console.error("need puppeteer-core: npm i puppeteer-core@^23"); process.exit(2); }

const CHROME_CANDIDATES = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser",
];
const chrome = CHROME_CANDIDATES.find(p => { try { return fs.statSync(p).isFile(); } catch { return false; } });
if (!chrome) { console.error("no Chrome binary found"); process.exit(2); }

const args = process.argv.slice(2);
const jsonOut = args.includes("--json");
const headful = args.includes("--headful");   // real GPU + vsync — measures backdrop-filter/composite cost
const pos = args.filter(a => !a.startsWith("--"));
const file = pos[0];
const speed = pos[1] || "800";
const measureMs = (+(pos[2] || 12)) * 1000;
if (!file) { console.error("usage: node tests/bench.js <html> [speed] [seconds]"); process.exit(2); }

const TILE_HOSTS = ["server.arcgisonline.com", "basemaps.cartocdn.com"];
const pctl = (a, p) => a.length ? a[Math.min(a.length - 1, Math.floor(p / 100 * a.length))] : 0;

(async () => {
  const browser = await puppeteer.launch({
    executablePath: chrome, headless: headful ? false : "new",
    args: ["--no-sandbox", "--disable-dev-shm-usage", "--window-size=1440,900",
           "--hide-scrollbars", "--mute-audio"],
  });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 1 });

    // block tiles for determinism, allow the Leaflet CDN
    await page.setRequestInterception(true);
    page.on("request", req => {
      const u = req.url();
      if (TILE_HOSTS.some(h => u.includes(h))) return req.abort();
      req.continue();
    });

    // record every animation frame's timestamp before any page script runs
    await page.evaluateOnNewDocument(() => {
      window.__frames = [];
      const raf = window.requestAnimationFrame.bind(window);
      window.requestAnimationFrame = cb => raf(t => { window.__frames.push(t); return cb(t); });
    });

    await page.goto("file://" + path.resolve(file), { waitUntil: "load", timeout: 30000 }).catch(() => {});

    // wait until the viewer is actually playing (play button shows the pause glyph)
    const playing = await page.waitForFunction(
      () => { const p = document.querySelector("#play"); return p && p.textContent === "❚❚"; },
      { timeout: 20000 }
    ).then(() => true).catch(() => false);
    if (!playing) {
      // nudge it: skip title overlay then press play
      await page.evaluate(() => { const o = document.querySelector("#titleOverlay"); if (o) o.click(); });
      await new Promise(r => setTimeout(r, 2600));
      await page.evaluate(() => { const p = document.querySelector("#play"); if (p && p.textContent === "▶") p.click(); });
      await new Promise(r => setTimeout(r, 400));
    }

    // pin the playback speed
    await page.evaluate(sp => {
      const b = [...document.querySelectorAll("#speeds button")].find(x => x.dataset.v === sp);
      if (b) b.click();
    }, speed);

    // start the measurement window: reset frame log + capture baseline metrics + start tracing
    await page.evaluate(() => { window.__frames.length = 0; window.__t0 = performance.now(); });
    const m0 = await page.metrics();
    const tracePath = path.join(require("os").tmpdir(), "replay-trace.json");
    await page.tracing.start({
      path: tracePath, screenshots: false,
      categories: ["devtools.timeline", "disabled-by-default-devtools.timeline.frame"],
    });

    // run until playback ends (play glyph back to ▶) or the measure window elapses
    await page.waitForFunction(
      mx => document.querySelector("#play").textContent === "▶" || (performance.now() - window.__t0) > mx,
      { timeout: measureMs + 8000, polling: 100 }, measureMs
    ).catch(() => {});

    await page.tracing.stop();
    const m1 = await page.metrics();
    const frames = await page.evaluate(() => window.__frames.slice());

    // parse the trace for rendering-pipeline cost (paint/layout/composite) + dropped frames
    const render = { Layout: 0, Paint: 0, UpdateLayerTree: 0, "CompositeLayers": 0,
                     RecalculateStyles: 0, RasterTask: 0 };
    let dropped = 0, presented = 0;
    try {
      const tr = JSON.parse(fs.readFileSync(tracePath, "utf8"));
      for (const e of (tr.traceEvents || [])) {
        if (e.ph === "X" && e.dur && render[e.name] !== undefined) render[e.name] += e.dur / 1000;
        if (e.name === "DroppedFrame") dropped++;
        if (e.name === "DrawFrame" || e.name === "Frame") presented++;
      }
    } catch {}

    await browser.close();

    const durs = [];
    for (let i = 1; i < frames.length; i++) durs.push(frames[i] - frames[i - 1]);
    const sorted = durs.slice().sort((a, b) => a - b);
    const n = durs.length || 1;
    const sum = durs.reduce((a, b) => a + b, 0);
    const mean = sum / n;
    const wall = (frames[frames.length - 1] - frames[0]) / 1000 || 1;
    const layouts = (m1.LayoutCount || 0) - (m0.LayoutCount || 0);
    const recalcs = (m1.RecalcStyleCount || 0) - (m0.RecalcStyleCount || 0);
    const res = {
      file: path.basename(file), speed: +speed, frames: frames.length, wallSec: +wall.toFixed(2),
      fps: +(frames.length / wall).toFixed(1),
      frameMs: { mean: +mean.toFixed(2), p50: +pctl(sorted, 50).toFixed(2),
                 p95: +pctl(sorted, 95).toFixed(2), p99: +pctl(sorted, 99).toFixed(2),
                 max: +Math.max(0, ...durs).toFixed(2) },
      jank: { over16: +(durs.filter(d => d > 16.7).length / n * 100).toFixed(1),
              over33: +(durs.filter(d => d > 33.3).length / n * 100).toFixed(1) },
      perFrame: { layouts: +(layouts / n).toFixed(2), recalcs: +(recalcs / n).toFixed(2) },
      heapMB: +(((m1.JSHeapUsedSize || 0)) / 1048576).toFixed(1),
      renderMs: Object.fromEntries(Object.entries(render).map(([k, v]) => [k, +v.toFixed(1)])),
      renderTotalMs: +Object.values(render).reduce((a, b) => a + b, 0).toFixed(1),
      droppedFrames: dropped,
    };
    res.renderMsPerFrame = +(res.renderTotalMs / n).toFixed(3);

    if (jsonOut) { console.log(JSON.stringify(res)); return; }
    console.log(`\n⏱  ${res.file}  @ ${res.speed}×   (${res.frames} frames / ${res.wallSec}s)`);
    console.log(`   FPS ${res.fps}   frame ms: p50 ${res.frameMs.p50}  p95 ${res.frameMs.p95}  p99 ${res.frameMs.p99}  max ${res.frameMs.max}`);
    console.log(`   jank: ${res.jank.over16}% > 16.7ms (60fps miss) · ${res.jank.over33}% > 33ms (30fps miss)   dropped frames: ${res.droppedFrames}`);
    console.log(`   main thread/frame: ${res.perFrame.layouts} layouts · ${res.perFrame.recalcs} recalcs   heap ${res.heapMB} MB`);
    console.log(`   render pipeline (total over window): ${res.renderTotalMs}ms  (${res.renderMsPerFrame}ms/frame)`);
    console.log(`     Layout ${res.renderMs.Layout}  Paint ${res.renderMs.Paint}  Composite ${res.renderMs.CompositeLayers}  LayerTree ${res.renderMs.UpdateLayerTree}  Raster ${res.renderMs.RasterTask}  Style ${res.renderMs.RecalculateStyles}`);
  } catch (e) {
    try { await browser.close(); } catch {}
    console.error("bench error:", e.message);
    process.exit(1);
  }
})();
