"""WEB-1 (HAY-125): build_analytics.py -> analytics.html

Builds a SELF-CONTAINED static analytics page. All data is baked into the HTML
as JSON; the only external dependency is Chart.js loaded from a CDN. No server,
no build step, no npm.

Two analytics metrics are shown SIDE BY SIDE:

  (a) HEADLINE  -- MEASURED daily/trip weight-per-inch by year. This comes
      straight from the weigh-in anchor tables (daily_weights.csv); it is ground
      truth (each day's measured bag / that day's total inches).

  (b) SECONDARY -- MODELED per-catch weight/inch from analysis.py's calibrated
      power curve (W = a * L**b). Clearly labelled "modeled (b assumed, not
      fitted)" because the exponent b is the literature default until enough
      individual fish weights are logged to fit our own.

Interactive client-side filters: year, species, fisherman, kept/released. Plus
length distribution, catch counts, and bag by day/trip. Degrades gracefully for
small-n (e.g. 2025 walleye n=11, 2026 daily wt/inch absent).

Run:
    uv run --with pandas python build_analytics.py
"""

import glob
import html
import json
import os

import numpy as np
import pandas as pd

# Pull the DATA-1 loader + power-curve estimator from analysis.py. Importing the
# module runs its top-level demo (a load_data() + fig build); that is harmless
# here -- we only consume the functions below.
import analysis

# WEB-3: pure-Python lake-area lookup (reuses the PIPE-1 areas.geojson helper).
# Optional — if areas.py / areas.geojson aren't present, catches just have no area.
try:
    import areas as _areas
except Exception:  # pragma: no cover - areas are an optional enrichment
    _areas = None

ROOTS = ("historical", os.path.join("exports", "2026"))
OUT_HTML = "analytics.html"

# Per-catch CSV columns we surface to the client (read defensively / by name).
RAW_COLS = [
    "id", "year", "weigh_session_id", "trip", "fisherman", "species", "kept",
    "length_in", "depth_ft", "timestamp_local", "lure_color1", "lure_color2",
    "bait", "location_name", "lat", "lon",
]


def _safe_num(series):
    return pd.to_numeric(series, errors="coerce")


def load_raw_catches(roots=ROOTS):
    """Every catches.csv under the roots, ALL species, kept AND released.

    This is the payload the client filters on. It is intentionally broader than
    analysis.load_history() (which is walleye/kept-only for bag calibration).
    """
    files = []
    for root in roots:
        files += sorted(glob.glob(os.path.join(root, "**", "catches.csv"),
                                  recursive=True))
    frames = []
    for p in files:
        df = pd.read_csv(p)
        # Keep only known columns that exist; tolerate schema drift.
        cols = [c for c in RAW_COLS if c in df.columns]
        frames.append(df[cols].copy())
    raw = (pd.concat(frames, ignore_index=True)
           if frames else pd.DataFrame(columns=RAW_COLS))

    raw["length_in"] = _safe_num(raw.get("length_in"))
    raw["depth_ft"] = _safe_num(raw.get("depth_ft"))
    raw["lat"] = _safe_num(raw.get("lat"))
    raw["lon"] = _safe_num(raw.get("lon"))
    raw["year"] = _safe_num(raw.get("year")).astype("Int64")
    # Normalize kept to a clean bool.
    raw["kept_bool"] = raw.get("kept").map(
        lambda v: str(v).strip().lower() in ("true", "1", "yes"))
    # Drop exact dupes (e.g. a session re-exported across folders).
    if "id" in raw and "weigh_session_id" in raw:
        raw = raw.drop_duplicates(subset=["weigh_session_id", "id", "timestamp_local"])
    return raw.reset_index(drop=True)


def build_catch_records(raw):
    """Tidy list-of-dicts for the client. Strings are passed raw here and HTML-
    escaped at render time in the page (and again defensively below)."""
    ts = pd.to_datetime(raw.get("timestamp_local"), errors="coerce")
    recs = []
    for i, (_, r) in enumerate(raw.iterrows()):
        length = r["length_in"]
        t = ts.iloc[i] if i < len(ts) else pd.NaT
        # WEB-3: point-in-polygon area label from areas.geojson (PIPE-1 helper),
        # so analytics can filter/label catches by named lake area.
        area = None
        if _areas is not None and pd.notna(r.get("lat")) and pd.notna(r.get("lon")):
            area = _areas.assign_area(r["lat"], r["lon"])
        recs.append({
            "year": int(r["year"]) if pd.notna(r["year"]) else None,
            "trip": _clean(r.get("trip")),
            "fisherman": _clean(r.get("fisherman")),
            "species": _clean(r.get("species")),
            "kept": bool(r["kept_bool"]),
            "length": float(length) if pd.notna(length) else None,
            "depth": float(r["depth_ft"]) if pd.notna(r.get("depth_ft")) else None,
            # hour and minutes-since-8AM power the time-of-day plots (8 AM start,
            # mirroring analysis.ipynb's 12-hour clock view).
            "hour": int(t.hour) if pd.notna(t) else None,
            "min_since_8am": int((t.hour - 8) * 60 + t.minute) if pd.notna(t) else None,
            "session": _clean(r.get("weigh_session_id")),
            "location": _clean(r.get("location_name")),
            "area": area,
        })
    return recs


def _clean(v):
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return None
    s = str(v).strip()
    return s if s and s.lower() != "nan" else None


def load_measured_daily(roots=ROOTS):
    """HEADLINE (a): measured daily/trip weight-per-inch by year.

    Routed through analysis.load_history() so every fix in the loader applies:
      * day_inches is DERIVED from the kept-walleye length sum where it was left
        blank (2026 sessions), so those rows now carry a measured wt/inch;
      * the NET_TARE_LBS_BY_YEAR reconciliation (if a human enables it) is already
        applied to daily_wt_lbs before wt/inch is computed.
    This keeps the MEASURED headline consistent with the MODELED panel, which
    consumes the same load_history() bag basis.
    """
    _, d = analysis.load_history(roots=roots)
    if d.empty:
        return pd.DataFrame()
    d = d.copy()
    d["weigh_date"] = pd.to_datetime(d["weigh_date"])
    if "year" not in d.columns:
        d["year"] = d["weigh_date"].dt.year
    return d.reset_index(drop=True)


def build_headline(daily):
    """Per-year MEASURED wt/inch: weighted by inches (sum bag / sum inches) over
    rows that actually have inches, plus per-session detail."""
    sessions = []
    by_year = {}
    for _, r in daily.iterrows():
        wpi = r.get("daily_wt_per_inch")
        sessions.append({
            "year": int(r["year"]),
            "session": _clean(r.get("weigh_session_id")),
            "trip": _clean(r.get("trip")),
            "weigh_date": r["weigh_date"].strftime("%Y-%m-%d"),
            "bag_lbs": float(r["daily_wt_lbs"]) if pd.notna(r.get("daily_wt_lbs")) else None,
            "day_inches": float(r["day_inches"]) if pd.notna(r.get("day_inches")) else None,
            "wt_per_inch": float(wpi) if pd.notna(wpi) else None,
        })
    has_inches = daily.dropna(subset=["day_inches", "daily_wt_lbs"])
    for year, g in has_inches.groupby(has_inches["year"]):
        inches = g["day_inches"].sum()
        bag = g["daily_wt_lbs"].sum()
        by_year[int(year)] = {
            "wt_per_inch": float(bag / inches) if inches else None,
            "n_sessions": int(len(g)),
            "total_bag_lbs": float(bag),
            "total_inches": float(inches),
        }
    return {"by_year": by_year, "sessions": sessions}


def build_modeled(b_used, fit):
    """SECONDARY (b): MODELED per-catch wt/inch from the calibrated power curve.

    Uses analysis.load_history() (walleye/kept) + estimate_weights(). Reports a
    per-year mean of weight_est/length and the per-catch points for plotting.
    Labelled in the UI as 'modeled (b assumed, not fitted)'.
    """
    fish, daily = analysis.load_history()
    if fish.empty or daily.empty:
        return {"by_year": {}, "points": [], "b": b_used, "fitted": bool(fit)}
    fish = analysis.estimate_weights(fish.copy(), daily, b_used)
    fish["wt_per_inch"] = fish["weight_est"] / fish["length"]

    by_year, points = {}, []
    for year, g in fish.groupby(fish["year"]):
        # Bag-weighted wt/inch (sum weight_est / sum length) so the MODELED panel
        # uses the SAME basis as the MEASURED headline (bag / inches). A plain mean
        # of per-fish ratios would diverge from the measured ground truth.
        by_year[int(year)] = {
            "wt_per_inch_mean": float(g["weight_est"].sum() / g["length"].sum()),
            "n": int(len(g)),
        }
    for _, r in fish.iterrows():
        points.append({
            "year": int(r["year"]),
            "length": float(r["length"]),
            "weight_est": float(r["weight_est"]),
            "wt_per_inch": float(r["wt_per_inch"]),
        })
    return {"by_year": by_year, "points": points, "b": float(b_used),
            "fitted": bool(fit)}


def build_payload():
    raw = load_raw_catches()
    catches = build_catch_records(raw)

    daily = load_measured_daily()
    headline = build_headline(daily) if not daily.empty else {"by_year": {}, "sessions": []}

    fit = analysis.fit_length_weight(analysis.load_history()[0])
    b_used = fit["b"] if fit else analysis.B_LITERATURE
    modeled = build_modeled(b_used, fit)

    years = sorted({c["year"] for c in catches if c["year"] is not None})
    species = sorted({c["species"] for c in catches if c["species"]})
    fishers = sorted({c["fisherman"] for c in catches if c["fisherman"]})
    area_list = sorted({c["area"] for c in catches if c["area"]})

    return {
        "generated_roots": list(ROOTS),
        "catches": catches,
        "headline": headline,            # (a) measured wt/inch
        "modeled": modeled,              # (b) modeled wt/inch (assumed, not fitted)
        "facets": {"years": years, "species": species, "fishers": fishers,
                   "areas": area_list},
        "counts": {"catches": len(catches),
                   "weigh_sessions": len(headline.get("sessions", []))},
    }


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Fishing Analytics &mdash; Lake Oahe Walleye</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js"></script>
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js" charset="utf-8"></script>
<style>
  :root {{ --bg:#0e1116; --panel:#171c24; --ink:#e7edf3; --muted:#9aa7b4;
           --line:#283342; --accent:#5bb4ff; --accent2:#ffce5b; --good:#6fd08c; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink);
          font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }}
  header {{ padding:24px 28px 8px; }}
  h1 {{ margin:0 0 4px; font-size:22px; }}
  .sub {{ color:var(--muted); font-size:13px; }}
  main {{ padding:16px 28px 60px; max-width:1200px; }}
  .filters {{ display:flex; flex-wrap:wrap; gap:14px; margin:18px 0 8px;
              background:var(--panel); border:1px solid var(--line);
              border-radius:10px; padding:14px 16px; }}
  .filters label {{ display:flex; flex-direction:column; gap:4px; font-size:12px;
                    color:var(--muted); }}
  select {{ background:#0d1218; color:var(--ink); border:1px solid var(--line);
            border-radius:7px; padding:7px 9px; font-size:14px; min-width:140px; }}
  .grid {{ display:grid; grid-template-columns:1fr 1fr; gap:18px; margin-top:14px; }}
  .card {{ background:var(--panel); border:1px solid var(--line);
           border-radius:12px; padding:16px 18px; }}
  .card.full {{ grid-column:1 / -1; }}
  .card h2 {{ margin:0 0 2px; font-size:15px; }}
  .tag {{ display:inline-block; font-size:11px; padding:2px 8px; border-radius:999px;
          margin-left:8px; vertical-align:middle; }}
  .tag.measured {{ background:rgba(111,208,140,.16); color:var(--good);
                   border:1px solid rgba(111,208,140,.4); }}
  .tag.modeled {{ background:rgba(255,206,91,.14); color:var(--accent2);
                  border:1px solid rgba(255,206,91,.4); }}
  .note {{ color:var(--muted); font-size:12px; margin:2px 0 12px; }}
  .chart-wrap {{ position:relative; height:260px; }}
  .kpis {{ display:flex; gap:18px; flex-wrap:wrap; margin:6px 0 2px; }}
  .kpi {{ background:#0d1218; border:1px solid var(--line); border-radius:9px;
          padding:10px 14px; min-width:110px; }}
  .kpi .v {{ font-size:20px; font-weight:600; }}
  .kpi .l {{ font-size:11px; color:var(--muted); }}
  .empty {{ color:var(--muted); font-style:italic; padding:30px 0; text-align:center; }}
  .smalln {{ color:var(--accent2); font-size:12px; }}
  table {{ width:100%; border-collapse:collapse; font-size:13px; }}
  th,td {{ text-align:left; padding:6px 8px; border-bottom:1px solid var(--line); }}
  th {{ color:var(--muted); font-weight:600; }}
  footer {{ color:var(--muted); font-size:12px; padding:0 28px 40px; }}
</style>
</head>
<body>
<header>
  <h1>Fishing Analytics &mdash; Lake Oahe Walleye</h1>
  <div class="sub">Self-contained &middot; data baked in &middot;
    <span id="count-sub"></span></div>
</header>
<main>
  <div class="filters">
    <label>Year<select id="f-year"></select></label>
    <label>Species<select id="f-species"></select></label>
    <label>Fisherman<select id="f-fisher"></select></label>
    <label>Area<select id="f-area"></select></label>
    <label>Status<select id="f-kept">
      <option value="">All</option>
      <option value="kept">Kept</option>
      <option value="released">Released</option>
    </select></label>
  </div>

  <div class="grid">
    <div class="card">
      <h2>Weight per inch by year<span class="tag measured">measured (a)</span></h2>
      <div class="note">Ground truth: measured daily bag &divide; total inches,
        per year. Not affected by the filters.</div>
      <div class="chart-wrap"><canvas id="c-measured"></canvas></div>
    </div>
    <div class="card">
      <h2>Weight per inch by year<span class="tag modeled">modeled (b)</span></h2>
      <div class="note">Modeled per-catch wt/inch from the calibrated power curve
        W = a&middot;L<sup>b</sup>. <b>b assumed, not fitted</b>
        (<span id="b-note"></span>). Walleye, kept only.</div>
      <div class="chart-wrap"><canvas id="c-modeled"></canvas></div>
    </div>

    <div class="card full">
      <div class="kpis" id="kpis"></div>
    </div>

    <div class="card">
      <h2>Length distribution</h2>
      <div class="note">Filtered catches, by 1-inch bins.</div>
      <div class="chart-wrap"><canvas id="c-length"></canvas></div>
    </div>
    <div class="card">
      <h2>Catch counts by species</h2>
      <div class="note">Filtered catches.</div>
      <div class="chart-wrap"><canvas id="c-species"></canvas></div>
    </div>

    <div class="card full">
      <h2>Length vs. depth</h2>
      <div class="note">Filtered catches. Uniform markers colored by year;
        depth plotted downward.</div>
      <div id="p-lendepth" style="height:420px;"></div>
    </div>

    <div class="card full">
      <h2>Time of day &mdash; catches &amp; average length by hour</h2>
      <div class="note">Filtered catches, 8 AM&ndash;8 PM with 12-hour tick labels.
        Bars = catches per hour; gold line = avg length by hour (right axis).</div>
      <div id="p-timeofday" style="height:440px;"></div>
    </div>

    <div class="card">
      <h2>Depth distribution by year</h2>
      <div class="note">Filtered catches. Violin per year (Plotly).</div>
      <div id="p-violin-depth" style="height:400px;"></div>
    </div>
    <div class="card">
      <h2>Length distribution by year</h2>
      <div class="note">Filtered catches. Violin per year (Plotly).</div>
      <div id="p-violin-length" style="height:400px;"></div>
    </div>

    <div class="card full">
      <h2>Length histogram (Plotly)</h2>
      <div class="note">Filtered catches, 1-inch bins.</div>
      <div id="p-hist-length" style="height:340px;"></div>
    </div>

    <div class="card full">
      <h2>Measured bag by weigh session (day / trip)
        <span class="tag measured">measured (a)</span></h2>
      <div class="note">From the weigh-in sheet. wt/inch shown where day inches
        were recorded (some 2026 sessions have none &mdash; shown as &mdash;).</div>
      <div id="bag-table"></div>
    </div>
  </div>
</main>
<footer>
  Generated by build_analytics.py from {roots}.
  Metric (a) is measured ground truth; metric (b) is a model whose exponent b is
  assumed (literature default) until enough individual fish weights are logged to
  fit it. Small-n years are flagged.
</footer>

<script id="payload" type="application/json">{payload_json}</script>
<script>
const DATA = JSON.parse(document.getElementById('payload').textContent);
const SMALL_N = 12; // flag years with fewer kept walleye than this

function esc(s) {{
  if (s === null || s === undefined) return '';
  return String(s).replace(/[&<>"']/g, c => (
    {{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));
}}
function el(id) {{ return document.getElementById(id); }}

// ---- populate filter dropdowns -------------------------------------------
function opt(v, label) {{ const o=document.createElement('option');
  o.value=v; o.textContent=label; return o; }}
function fillSelect(sel, values, allLabel) {{
  sel.appendChild(opt('', allLabel));
  values.forEach(v => sel.appendChild(opt(String(v), String(v))));
}}
fillSelect(el('f-year'), DATA.facets.years, 'All years');
fillSelect(el('f-species'), DATA.facets.species, 'All species');
fillSelect(el('f-fisher'), DATA.facets.fishers, 'All fishermen');
fillSelect(el('f-area'), DATA.facets.areas || [], 'All areas');
el('count-sub').textContent =
  DATA.counts.catches + ' catches · ' + DATA.counts.weigh_sessions + ' weigh sessions';
el('b-note').textContent = DATA.modeled.fitted
  ? ('b = ' + DATA.modeled.b.toFixed(3) + ', fitted')
  : ('b = ' + DATA.modeled.b.toFixed(3) + ', literature default');

// ---- chart helpers --------------------------------------------------------
Chart.defaults.color = '#9aa7b4';
Chart.defaults.borderColor = '#283342';
Chart.defaults.font.family = '-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif';
const charts = {{}};
function draw(id, cfg) {{
  if (charts[id]) charts[id].destroy();
  charts[id] = new Chart(el(id), cfg);
}}
function emptyState(id, msg) {{
  if (charts[id]) {{ charts[id].destroy(); delete charts[id]; }}
  const c = el(id), ctx = c.getContext('2d');
  ctx.clearRect(0,0,c.width,c.height);
  ctx.fillStyle = '#9aa7b4'; ctx.font = '13px sans-serif';
  ctx.textAlign='center';
  ctx.fillText(msg, c.width/2, c.height/2);
}}

// ---- (a) measured wt/inch by year (static, not filtered) ------------------
function drawMeasured() {{
  const by = DATA.headline.by_year || {{}};
  const years = Object.keys(by).sort();
  if (!years.length) {{ emptyState('c-measured', 'No measured wt/inch available'); return; }}
  draw('c-measured', {{
    type:'bar',
    data:{{ labels:years, datasets:[{{
      label:'measured wt/inch', backgroundColor:'#6fd08c',
      data: years.map(y => by[y].wt_per_inch) }}]}},
    options:{{ responsive:true, maintainAspectRatio:false,
      plugins:{{ legend:{{display:false}}, tooltip:{{ callbacks:{{
        afterLabel: (i)=> {{ const d=by[i.label];
          return d.n_sessions+' sessions · '+d.total_bag_lbs.toFixed(1)
            +' lbs / '+d.total_inches.toFixed(0)+' in'; }} }}}} }},
      scales:{{ y:{{ title:{{display:true,text:'lbs / inch'}}, beginAtZero:true }} }} }}
  }});
}}

// ---- (b) modeled wt/inch by year (static; from walleye/kept model) --------
function drawModeled() {{
  const by = DATA.modeled.by_year || {{}};
  const years = Object.keys(by).sort();
  if (!years.length) {{ emptyState('c-modeled', 'No modeled data available'); return; }}
  draw('c-modeled', {{
    type:'bar',
    data:{{ labels:years, datasets:[{{
      label:'modeled wt/inch', backgroundColor:'#ffce5b',
      data: years.map(y => by[y].wt_per_inch_mean) }}]}},
    options:{{ responsive:true, maintainAspectRatio:false,
      plugins:{{ legend:{{display:false}}, tooltip:{{ callbacks:{{
        afterLabel: (i)=> {{ const d=by[i.label];
          const flag = d.n < SMALL_N ? '  ⚠ small n' : '';
          return 'n=' + d.n + flag; }} }}}} }},
      scales:{{ y:{{ title:{{display:true,text:'lbs / inch (modeled)'}}, beginAtZero:true }} }} }}
  }});
}}

// ---- filtering ------------------------------------------------------------
function currentFilter() {{
  return {{
    year: el('f-year').value,
    species: el('f-species').value,
    fisher: el('f-fisher').value,
    area: el('f-area').value,
    kept: el('f-kept').value,
  }};
}}
function applyFilter(f) {{
  return DATA.catches.filter(c => {{
    if (f.year && String(c.year) !== f.year) return false;
    if (f.species && c.species !== f.species) return false;
    if (f.fisher && c.fisherman !== f.fisher) return false;
    if (f.area && c.area !== f.area) return false;
    if (f.kept === 'kept' && !c.kept) return false;
    if (f.kept === 'released' && c.kept) return false;
    return true;
  }});
}}

function drawLength(rows) {{
  const lens = rows.map(r => r.length).filter(v => v !== null && !isNaN(v));
  if (!lens.length) {{ emptyState('c-length', 'No length data for this filter'); return; }}
  const lo = Math.floor(Math.min(...lens)), hi = Math.ceil(Math.max(...lens));
  const bins = {{}}; for (let b=lo; b<=hi; b++) bins[b]=0;
  lens.forEach(v => {{ const b=Math.floor(v); bins[b]=(bins[b]||0)+1; }});
  const labels = Object.keys(bins).sort((a,b)=>a-b);
  draw('c-length', {{
    type:'bar',
    data:{{ labels: labels.map(b=>b+'"'), datasets:[{{
      label:'catches', backgroundColor:'#5bb4ff',
      data: labels.map(b=>bins[b]) }}]}},
    options:{{ responsive:true, maintainAspectRatio:false,
      plugins:{{legend:{{display:false}}}},
      scales:{{ y:{{ beginAtZero:true, title:{{display:true,text:'count'}} }},
                x:{{ title:{{display:true,text:'length (in)'}} }} }} }}
  }});
}}

function drawSpecies(rows) {{
  if (!rows.length) {{ emptyState('c-species', 'No catches for this filter'); return; }}
  const counts = {{}};
  rows.forEach(r => {{ const s = r.species || '(unknown)';
    counts[s] = (counts[s]||0)+1; }});
  const labels = Object.keys(counts).sort((a,b)=>counts[b]-counts[a]);
  draw('c-species', {{
    type:'bar',
    data:{{ labels, datasets:[{{ label:'catches', backgroundColor:'#5bb4ff',
      data: labels.map(s=>counts[s]) }}]}},
    options:{{ indexAxis:'y', responsive:true, maintainAspectRatio:false,
      plugins:{{legend:{{display:false}}}},
      scales:{{ x:{{ beginAtZero:true, title:{{display:true,text:'count'}} }} }} }}
  }});
}}

function drawKpis(rows) {{
  const n = rows.length;
  const kept = rows.filter(r=>r.kept).length;
  const lens = rows.map(r=>r.length).filter(v=>v!==null && !isNaN(v));
  const avg = lens.length ? (lens.reduce((a,b)=>a+b,0)/lens.length) : null;
  const mx = lens.length ? Math.max(...lens) : null;
  // small-n flag using filtered year's modeled n if a single year is selected
  const f = currentFilter();
  let flag = '';
  if (f.year && DATA.modeled.by_year[f.year]
      && DATA.modeled.by_year[f.year].n < SMALL_N) {{
    flag = '<span class="smalln">⚠ small sample (n='
      + DATA.modeled.by_year[f.year].n + ' kept walleye)</span>';
  }}
  el('kpis').innerHTML =
    kpi(n, 'catches (filtered)') +
    kpi(kept + ' / ' + (n - kept), 'kept / released') +
    kpi(avg!==null ? avg.toFixed(1)+'"' : '—', 'avg length') +
    kpi(mx!==null ? mx.toFixed(1)+'"' : '—', 'max length') +
    (flag ? '<div class="kpi"><div class="v">⚠</div><div class="l">'+flag+'</div></div>' : '');
}}
function kpi(v, l) {{
  return '<div class="kpi"><div class="v">'+esc(v)+'</div><div class="l">'+esc(l)+'</div></div>';
}}

function drawBagTable() {{
  const s = DATA.headline.sessions || [];
  if (!s.length) {{ el('bag-table').innerHTML = '<div class="empty">No weigh sessions.</div>'; return; }}
  let h = '<table><thead><tr><th>Date</th><th>Trip</th><th>Bag (lbs)</th>'
    + '<th>Day inches</th><th>wt/inch</th></tr></thead><tbody>';
  s.slice().sort((a,b)=>a.weigh_date<b.weigh_date?-1:1).forEach(r => {{
    h += '<tr><td>'+esc(r.weigh_date)+'</td><td>'+esc(r.trip)+'</td>'
      + '<td>'+(r.bag_lbs!==null?r.bag_lbs.toFixed(2):'—')+'</td>'
      + '<td>'+(r.day_inches!==null?r.day_inches.toFixed(1):'—')+'</td>'
      + '<td>'+(r.wt_per_inch!==null?r.wt_per_inch.toFixed(4):'—')+'</td></tr>';
  }});
  h += '</tbody></table>';
  el('bag-table').innerHTML = h;
}}

// ---- Plotly plots ported from analysis.ipynb (respect the filters) --------
const PLOTLY_LAYOUT = {{
  paper_bgcolor:'rgba(0,0,0,0)', plot_bgcolor:'rgba(0,0,0,0)',
  font:{{color:'#9aa7b4', family:'-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif'}},
  margin:{{l:55,r:20,t:20,b:50}},
}};
const PLOTLY_CFG = {{responsive:true, displayModeBar:false}};
const PALETTE = ['#5bb4ff','#ffce5b','#6fd08c','#ff8a8a','#c89bff','#7fe3d4'];
function yearColor(y, years) {{ return PALETTE[years.indexOf(y) % PALETTE.length]; }}

// depth is stored positive in the CSV; mirror the notebook and plot it downward.
function depthDown(v) {{ return v === null ? null : -Math.abs(v); }}

// crisp categorical year palette tuned for the dark bg
const YEAR_COLORS = {{2023:'#4ea7fc', 2024:'#f5b301', 2025:'#34d399', 2026:'#f87171'}};
function lenDepthColor(y) {{ return YEAR_COLORS[y] || '#cbd5e1'; }}

function drawLenDepth(rows) {{
  const d = rows.filter(r => r.length !== null && r.depth !== null && !isNaN(r.length) && !isNaN(r.depth));
  const div = el('p-lendepth');
  if (!d.length) {{ Plotly.purge(div); div.innerHTML = '<div class="empty">No length/depth data for this filter</div>'; return; }}
  const years = [...new Set(d.map(r => r.year))].sort();
  const traces = years.map(y => {{
    const s = d.filter(r => r.year === y);
    return {{ x:s.map(r=>r.length), y:s.map(r=>depthDown(r.depth)), mode:'markers',
      type:'scatter', name:String(y),
      // uniform small markers w/ thin dark outline so points separate
      marker:{{ size:8, color:lenDepthColor(y), opacity:0.7,
                line:{{width:0.6, color:'rgba(0,0,0,0.45)'}} }},
      customdata:s.map(r=>[r.species||'—', r.fisherman||r.fisher||'—']),
      text:s.map(r=>r.length),
      hovertemplate:String(y)+' · %{{x}}" · %{{y:.0f}} ft'
        +'<br>%{{customdata[0]}} · %{{customdata[1]}}<extra></extra>' }};
  }});
  Plotly.react(div, traces, Object.assign({{}}, PLOTLY_LAYOUT, {{
    xaxis:{{title:'Length (inches)', gridcolor:'#283342'}},
    yaxis:{{title:'Depth (feet)', gridcolor:'#283342'}},
    showlegend:true, legend:{{orientation:'h'}} }}), PLOTLY_CFG);
}}

function drawTimeOfDay(rows) {{
  const d = rows.filter(r => r.hour !== null && r.hour !== undefined);
  const div = el('p-timeofday');
  if (!d.length) {{ Plotly.purge(div); div.innerHTML = '<div class="empty">No timestamped catches for this filter</div>'; return; }}
  // aggregate per hour: count + avg length (8 AM..8 PM)
  const agg = {{}};
  d.forEach(r => {{ const h=r.hour; (agg[h] = agg[h] || {{n:0, sum:0, ln:0}});
    agg[h].n++; if (r.length!==null && !isNaN(r.length)) {{ agg[h].sum+=r.length; agg[h].ln++; }} }});
  const hours = []; for (let h=8; h<=20; h++) hours.push(h);
  const fmt = h => (h%12||12) + (h<12 ? 'a':'p');
  const labels = hours.map(fmt);
  const counts = hours.map(h => agg[h] ? agg[h].n : 0);
  const avgLen = hours.map(h => (agg[h] && agg[h].ln) ? agg[h].sum/agg[h].ln : null);
  // tiny count labels atop bars (blank for empty hours)
  const countText = counts.map(c => c ? String(c) : '');
  // per-bar hover text: count caught and avg length
  const barHover = hours.map(h => {{ const a=agg[h];
    return a ? a.n+' caught · avg '+(a.ln ? (a.sum/a.ln).toFixed(1) : '—')+'"' : '0 caught'; }});
  // color each bar by that hour's avg length, bounded to the observed range so variation shows
  const lenVals = avgLen.filter(v => v !== null && !isNaN(v));
  const cmin = lenVals.length ? Math.floor(Math.min(...lenVals)) : 12;
  const cmax = lenVals.length ? Math.ceil(Math.max(...lenVals)) : 18;
  // empty hours have no avg length; pin them to cmin so the color array stays numeric
  const barColors = avgLen.map(v => (v !== null && !isNaN(v)) ? v : cmin);
  const bars = {{ x:labels, y:counts, type:'bar', name:'catches', yaxis:'y',
    marker:{{ color:barColors, colorscale:'Turbo', cmin:cmin, cmax:cmax,
      colorbar:{{ title:{{text:'avg length (in)'}}, x:1.12, thickness:12, len:0.85 }} }},
    text:countText, textposition:'outside', textfont:{{color:'#cbd5e1', size:11}},
    cliponaxis:false, hovertext:barHover, hovertemplate:'%{{hovertext}}<extra></extra>' }};
  const line = {{ x:labels, y:avgLen, type:'scatter', mode:'lines+markers',
    name:'avg length', yaxis:'y2', connectgaps:true,
    line:{{color:'#f5b301', width:2.5}}, marker:{{color:'#f5b301', size:6}},
    hovertemplate:'avg %{{y:.1f}}"<extra></extra>' }};
  const maxc = Math.max(1, ...counts);
  // explicit, padded, ascending secondary range from observed avg lengths
  const avgVals = avgLen.filter(v => v !== null && !isNaN(v));
  const y2lo = avgVals.length ? Math.floor(Math.min(...avgVals)) - 1 : 12;
  const y2hi = avgVals.length ? Math.ceil(Math.max(...avgVals)) + 1 : 18;
  Plotly.react(div, [bars, line], Object.assign({{}}, PLOTLY_LAYOUT, {{
    xaxis:{{title:'Time of day (8 AM – 8 PM)', type:'category', tickangle:0}},
    yaxis:{{title:'Catches', range:[0, maxc*1.25], gridcolor:'#283342'}},
    yaxis2:{{title:'avg length (in)', overlaying:'y', side:'right', showgrid:false,
             range:[y2lo, y2hi]}},
    showlegend:true, legend:{{orientation:'h'}} }}), PLOTLY_CFG);
}}

function drawViolin(divId, rows, valueFn, axisTitle, downward) {{
  const div = el(divId);
  const d = rows.filter(r => {{ const v=valueFn(r); return v!==null && !isNaN(v); }});
  if (!d.length) {{ Plotly.purge(div); div.innerHTML = '<div class="empty">No data for this filter</div>'; return; }}
  const years = [...new Set(d.map(r => r.year))].sort();
  const traces = years.map(y => {{
    const s = d.filter(r => r.year === y);
    return {{ type:'violin', y:s.map(r => {{ const v=valueFn(r); return downward ? depthDown(v) : v; }}),
      x:s.map(()=>String(y)), name:String(y)+' (n='+s.length+')',
      box:{{visible:true}}, meanline:{{visible:true}}, points:'all', pointpos:0,
      line:{{color:yearColor(y, years)}} }};
  }});
  Plotly.react(div, traces, Object.assign({{}}, PLOTLY_LAYOUT, {{
    yaxis:{{title:axisTitle, gridcolor:'#283342'}}, xaxis:{{title:'Year'}},
    violinmode:'group', showlegend:true, legend:{{orientation:'h'}} }}), PLOTLY_CFG);
}}

function drawHistLength(rows) {{
  const div = el('p-hist-length');
  const lens = rows.map(r=>r.length).filter(v=>v!==null && !isNaN(v));
  if (!lens.length) {{ Plotly.purge(div); div.innerHTML = '<div class="empty">No length data for this filter</div>'; return; }}
  Plotly.react(div, [{{ x:lens, type:'histogram', xbins:{{size:1}},
    marker:{{color:'#5bb4ff'}} }}], Object.assign({{}}, PLOTLY_LAYOUT, {{
    xaxis:{{title:'Length (inches)', gridcolor:'#283342'}},
    yaxis:{{title:'Count', gridcolor:'#283342'}}, bargap:0.04 }}), PLOTLY_CFG);
}}

function refreshFiltered() {{
  const rows = applyFilter(currentFilter());
  drawLength(rows);
  drawSpecies(rows);
  drawKpis(rows);
  drawLenDepth(rows);
  drawTimeOfDay(rows);
  drawViolin('p-violin-depth', rows, r=>r.depth, 'Depth (feet)', true);
  drawViolin('p-violin-length', rows, r=>r.length, 'Length (inches)', false);
  drawHistLength(rows);
}}

['f-year','f-species','f-fisher','f-area','f-kept'].forEach(id =>
  el(id).addEventListener('change', refreshFiltered));

// initial render
drawMeasured();
drawModeled();
drawBagTable();
refreshFiltered();
</script>
</body>
</html>
"""


def main():
    payload = build_payload()
    # Escape any user-supplied strings that survive into the static table-driven
    # parts done client-side; the JSON itself is embedded inside a
    # <script type="application/json"> block, so we guard against the only HTML
    # break-out: a literal "</script>" appearing inside a string value.
    payload_json = json.dumps(payload, ensure_ascii=False)
    payload_json = payload_json.replace("</", "<\\/")  # neutralize </script>

    out = HTML_TEMPLATE.format(
        payload_json=payload_json,
        roots=html.escape(", ".join(payload["generated_roots"])),
    )
    with open(OUT_HTML, "w", encoding="utf-8") as f:
        f.write(out)

    print(f"Wrote {OUT_HTML} "
          f"({len(out):,} bytes, self-contained; Chart.js via CDN)")
    print(f"  catches: {payload['counts']['catches']}  "
          f"weigh sessions: {payload['counts']['weigh_sessions']}")
    print(f"  measured wt/inch by year: "
          f"{ {y: round(v['wt_per_inch'], 4) for y, v in payload['headline']['by_year'].items()} }")
    print(f"  modeled wt/inch by year (b={payload['modeled']['b']:.3f}, "
          f"{'fitted' if payload['modeled']['fitted'] else 'assumed'}): "
          f"{ {y: round(v['wt_per_inch_mean'], 4) for y, v in payload['modeled']['by_year'].items()} }")


if __name__ == "__main__":
    main()
