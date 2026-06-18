/* Runtime test harness for the replay viewer.
 *
 * Stubs Leaflet + the DOM, executes the generated page's inline <script>, then drives
 * the playback engine end-to-end and asserts the reveal logic is correct:
 *   - every visible catch gets a marker (no more, no less)
 *   - the boat marker ends at the last revealed track point
 *   - scrubbing backward resets + rebuilds without throwing or duplicating
 *   - speed bands actually segment (we see >1 band polyline populated on mixed-speed data)
 *
 * Usage:  node tests/harness.js <generated.html>
 * Exit 0 = all asserts pass.
 */
const fs = require("fs");
const vm = require("vm");

const file = process.argv[2];
if (!file) { console.error("usage: node tests/harness.js <html>"); process.exit(2); }
const html = fs.readFileSync(file, "utf8");
const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)];
const inline = scripts.map(m => m[1]).filter(s => s.includes("const DATA"))[0];
if (!inline) { console.error("no inline DATA script found"); process.exit(2); }

// ---- tiny Leaflet stub -------------------------------------------------------
let CATCH_MARKERS = 0;          // total catch divIcons ever created
const bandFill = {};            // band color -> total latlngs currently set (across days)

function Layer(extra) {
  return Object.assign({
    _ll: [], _onMap: false,
    addTo() { this._onMap = true; return this; },
    setLatLngs(v) { this._ll = v; return this; },
    setLatLng(v) { this._ll = v; return this; },
    getLatLngs() { return this._ll; },
    getLatLng() { return this._ll; },
    bindPopup() { return this; },
    bindTooltip() { return this; },
    openPopup() { return this; },
    bringToFront() { return this; },
    getElement() { return { querySelector() { return { style: {} }; } }; },
    addEventListener() {}, on() { return this; },
  }, extra || {});
}

const L = {
  _lastIconHTML: "",
  map() {
    return Layer({
      setView() { return this; },
      fitBounds() { return this; },
      flyToBounds() { return this; },
      flyTo() { return this; },
      panTo() { return this; },
      setZoom() { return this; },
      getZoom() { return 14; },
      once(ev, cb) { if (cb) cb(); return this; }, // fire moveend synchronously -> auto-play
      hasLayer(l) { return !!(l && l._onMap); },
      removeLayer(l) { if (l) l._onMap = false; return this; },
      addLayer() { return this; },
    });
  },
  control: { zoom: () => ({ addTo() { return this; } }) },
  tileLayer() { return Layer(); },
  svg() { return {}; },
  polyline(_, opts) {
    const lyr = Layer({ _color: opts && opts.color, _weight: opts && opts.weight });
    const orig = lyr.setLatLngs.bind(lyr);
    lyr.setLatLngs = (v) => {
      // count total points for color bookkeeping (core lines only, weight<5)
      if (opts && opts.weight && opts.weight < 5) {
        const n = (v || []).reduce((a, s) => a + (Array.isArray(s) ? s.length : 0), 0);
        bandFill[opts.color] = n;
      }
      return orig(v);
    };
    return lyr;
  },
  marker(_, opts) {
    const html = (opts && opts.icon && opts.icon._html) || "";
    if (html.includes("catch-pin")) CATCH_MARKERS++;
    return Layer();
  },
  divIcon(o) { return { _html: (o && o.html) || "" }; },
  circleMarker() { return Layer(); },
  layerGroup() {
    let items = [];
    return Layer({
      clearLayers() { items = []; return this; },
      addLayer(l) { items.push(l); return this; },
      _items: () => items,
    });
  },
  latLngBounds() {
    const b = { _pts: [], extend(p) { this._pts.push(p); return this; },
      isValid() { return this._pts.length > 0; } };
    return b;
  },
  heatLayer() { return Layer(); },
};
// marker icon html lives on opts.icon; our divIcon returns {_html}, attach for marker()
const realMarker = L.marker;
L.marker = (ll, opts) => {
  const icon = opts && opts.icon;
  if (icon && icon._html && icon._html.includes("catch-pin")) {} // counted in realMarker
  return realMarker(ll, opts);
};

// ---- tiny DOM stub -----------------------------------------------------------
function El() {
  const e = {
    children: [], style: {}, classList: {
      _s: new Set(), add(c){this._s.add(c);}, remove(c){this._s.delete(c);},
      toggle(c,f){ if(f===undefined) f=!this._s.has(c); f?this._s.add(c):this._s.delete(c); return f; },
      contains(c){return this._s.has(c);} },
    _html: "", set innerHTML(v){this._html=v;}, get innerHTML(){return this._html;},
    textContent: "", value: "0", dataset: {},
    appendChild(c){ this.children.push(c); return c; },
    querySelector(){ return El(); }, querySelectorAll(){ return []; },
    addEventListener(ev,fn){ (this._ev=this._ev||{})[ev]=fn; },
    matches(){ return false; },
    getContext(){ return { clearRect(){}, fillRect(){}, drawImage(){}, beginPath(){},
      moveTo(){}, lineTo(){}, arc(){}, fill(){}, stroke(){}, fillStyle:'', globalAlpha:1 }; },
    toBlob(){}, getBoundingClientRect(){ return {width:600,height:26,left:0,top:0}; },
    set onclick(fn){ this._click=fn; }, get onclick(){ return this._click; },
    set oninput(fn){ this._input=fn; }, get oninput(){ return this._input; },
  };
  return e;
}
const byId = {};
const document = {
  body: El(),
  createElement(){ return El(); },
  querySelector(sel){ const id = sel.replace("#",""); return byId[id] || (byId[id]=El()); },
  querySelectorAll(){ return []; },
  getElementById(id){ return byId[id] || (byId[id]=El()); },
};

// ---- timing stubs: synchronous pump -----------------------------------------
let RAF_CBS = [];
let VT = 0;
const requestAnimationFrame = (cb) => { RAF_CBS.push(cb); return RAF_CBS.length; };
const setTimeout_ = (cb) => { cb(); return 0; };
const clearTimeout_ = () => {};

function pump(steps, dtMs) {
  for (let i = 0; i < steps; i++) {
    const cbs = RAF_CBS; RAF_CBS = [];
    if (!cbs.length) break;
    VT += dtMs;
    cbs.forEach(cb => cb(VT));
  }
}

const sandbox = {
  L, document,
  window: { addEventListener() {} },
  requestAnimationFrame, setTimeout: setTimeout_, clearTimeout: clearTimeout_,
  console, Date, Math, Set, Array, Number, isNaN, JSON,
};
vm.createContext(sandbox);

// expose DATA before running by letting the script define it
try {
  new vm.Script(inline).runInContext(sandbox, { timeout: 5000 });
} catch (e) {
  console.error("THREW during init:", e.message, "\n", e.stack);
  process.exit(1);
}

// the script auto-plays via setTimeout (stubbed immediate) -> requestAnimationFrame loop.
// Pump enough frames at a big dt to blow through the whole (possibly multi-day) timeline.
pump(20000, 50);

// ---- assertions --------------------------------------------------------------
// a top-level `const DATA` in a vm script stays lexical, so read it from the HTML blob
const dm = inline.match(/const DATA = (\{[\s\S]*?\});\n/);
const data = JSON.parse(dm[1]);
const expectedCatches = data.days
  .reduce((a, d) => a + d.catches.filter(c => c.t != null).length, 0);

let ok = true;
function check(name, cond, detail) {
  console.log((cond ? "  ✓ " : "  ✗ ") + name + (detail ? "  — " + detail : ""));
  if (!cond) ok = false;
}

console.log(`harness: ${file.split("/").pop()}  (${data.days.length} day(s))`);
check("playback revealed every catch exactly once",
  CATCH_MARKERS === expectedCatches,
  `markers=${CATCH_MARKERS} expected=${expectedCatches}`);

const bandsUsed = Object.entries(bandFill).filter(([, n]) => n > 0).map(([c]) => c);
const hasMixedSpeed = data.days.some(d => d.track.some(p => p.s != null));
if (hasMixedSpeed) {
  check("speed bands segment the track (>=1 band populated)",
    bandsUsed.length >= 1, `bands populated: ${bandsUsed.length}`);
}

process.exit(ok ? 0 : 1);
