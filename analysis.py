import glob
import os

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# ---------------------------------------------------------------------------
# Weight model  (see docs/methodology.md and docs/adr/0001-weight-curve-estimation.md)
# ---------------------------------------------------------------------------
# W = a * L**b. The exponent defaults to the published walleye value; the
# coefficient `a` is calibrated per weigh-day so each day's estimates sum to the
# measured bag (ground truth). If enough individual `measured_wt_lbs` exist, the
# exponent is fitted from our own fish instead.
# Literature length-weight exponents for walleye, kept as a reference to measure our
# own (future) fitted exponent against. Our per-day MEASURED bags are the source of
# truth for now; switching b never changes a bag total (the per-day calibration
# reproduces it exactly) -- it only shifts the per-fish split.
#   b = 3.180  continental standard-weight equation (Murphy et al. 1990; Anderson & Neumann 1996)
#   b = 3.061  Lake Oahe, SD specific (Carlander's Handbook)
B_LITERATURE = 3.180        # default; see exponents above
WS_INTERCEPT = -3.643       # English-unit walleye standard-weight intercept (log10)
MIN_FIT_N = 12              # min individual weights to trust a fitted exponent

# ---------------------------------------------------------------------------
# NET-TARE reconciliation hook (non-destructive; DEFAULT EMPTY -> inert).
# ---------------------------------------------------------------------------
# Some years' bags were weighed WITH the landing net still on the scale (~2 lb),
# others net-free (2026 was net-free). To reconcile, a human can list a year here
# with the lbs to SUBTRACT PER WEIGH SESSION from that year's measured bag BEFORE
# any wt/inch (measured OR modeled) is computed. Example (do NOT enable yet):
#     NET_TARE_LBS_BY_YEAR = {2024: 2.0}
# Confirmed by owner (2026-06-21): 2023-2025 bags were weighed WITH the landing net
# on the scale (~2 lb); 2026 onward is weighed net-free. Net = 2.0 lb, subtracted per
# weigh session. Source CSVs/xlsx are NOT modified -- this correction lives only here.
NET_TARE_LBS_BY_YEAR = {2023: 2.0, 2024: 2.0, 2025: 2.0}   # year -> lbs/weigh-session

# Per-fish columns, read BY NAME (resilient to the often-changing column order).
PERFISH_COLS = ['id', 'year', 'fisherman', 'day', 'datetime', 'fish_species', 'kept',
                'length', 'depth', 'bait', 'weight_calc', 'location',
                'lure_color_1', 'lure_color_2', 'trip', 'weigh_date']


def load_data(path='fishing-trip.xlsx'):
    """Return (per-fish walleye dataframe, daily-weigh-in anchor table).

    Reads by column name. The optional per-fish individual-weight column
    `measured_wt_lbs` is picked up automatically when present.
    """
    full = pd.read_excel(path)

    fish = full[PERFISH_COLS].copy()
    fish['depth'] = fish['depth'] * -1                  # stored positive; plot downward
    fish['weigh_date'] = pd.to_datetime(fish['weigh_date'])
    # Optional individual weights (app-populated). Unique name -> read by name.
    fish['measured_wt_lbs'] = (pd.to_numeric(full['measured_wt_lbs'], errors='coerce')
                               if 'measured_wt_lbs' in full.columns else np.nan)
    fish = fish[fish['fish_species'] == 'walleye'].reset_index(drop=True)

    # Daily measured bags. `daily_wt_*` headers are unique; its weigh_date is the
    # duplicated header pandas renamed to 'weigh_date.1'.
    daily = full[['weigh_date.1', 'trip.1', 'daily_wt_lbs', 'day_inches', 'daily_wt_per_inch']].copy()
    daily.columns = ['weigh_date', 'trip', 'daily_wt_lbs', 'day_inches', 'daily_wt_per_inch']
    daily = daily[daily['daily_wt_per_inch'].notna()].copy()
    daily['weigh_date'] = pd.to_datetime(daily['weigh_date'])
    return fish, daily


def load_history(roots=('historical', os.path.join('exports', '2026'))):
    """NEW-schema loader (DATA-1 / app-build-plan LOCKED schema).

    Ingest every ``catches.csv`` + ``daily_weights.csv`` under the given roots
    (``historical/<year>/`` migrated rows + ``exports/2026/**`` app exports) into one
    tidy pair of frames shaped IDENTICALLY to what ``load_data()`` returns, so the rest
    of the pipeline (``estimate_weights`` etc.) consumes it unchanged.

    Returns ``(fish, daily)`` where:
      * ``fish`` is per-walleye, kept-only, with the legacy column names
        (``length``/``depth``/``fish_species``/``datetime``/``weigh_date``/``trip``)
        plus the join key ``weigh_session_id``. ``depth`` is sign-flipped (stored
        positive in CSV, negative for plotting, matching ``load_data()``).
      * ``daily`` is the weigh-session anchor table grouped by ``weigh_session_id``,
        filtered on ``daily_wt_lbs.notna()`` (the reviewed go-forward filter).

    Calibration groups by ``weigh_session_id``; ``kept==false`` rows are EXCLUDED from
    the per-fish frame (the bag denominator). Anchor rows are kept where
    ``daily_wt_lbs`` is present. Existing ``load_data()`` is untouched.
    """
    catch_files, daily_files = [], []
    for root in roots:
        catch_files += sorted(glob.glob(os.path.join(root, '**', 'catches.csv'), recursive=True))
        daily_files += sorted(glob.glob(os.path.join(root, '**', 'daily_weights.csv'), recursive=True))

    def _read_concat(paths):
        frames = [pd.read_csv(p) for p in paths]
        return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()

    raw = _read_concat(catch_files)
    daily = _read_concat(daily_files)

    # A weigh session can be re-exported across day folders (e.g. 2026-06-19
    # appears in both the 06-19 and 06-20 app exports), duplicating its catches.
    # Drop exact dupes by (session, id, timestamp) so per-session inch sums and
    # bag calibration aren't double-counted.
    dedup_keys = [k for k in ('weigh_session_id', 'id', 'timestamp_local')
                  if k in raw.columns]
    if dedup_keys:
        raw = raw.drop_duplicates(subset=dedup_keys).reset_index(drop=True)

    # --- per-fish: rename NEW schema -> legacy names the pipeline expects ----------
    fish = raw.rename(columns={
        'length_in': 'length', 'depth_ft': 'depth', 'species': 'fish_species',
        'timestamp_local': 'datetime', 'location_name': 'location',
        'lure_color1': 'lure_color_1', 'lure_color2': 'lure_color_2',
    }).copy()
    fish['datetime'] = pd.to_datetime(fish['datetime'])
    # weigh_date: derive from the session key ("hist-YYYY-MM-DD" or "YYYY-MM-DD").
    fish['weigh_date'] = pd.to_datetime(
        fish['weigh_session_id'].astype(str).str.replace('^hist-', '', regex=True))
    # kept may arrive as bool or "true"/"false" string; normalize then exclude false.
    kept = fish['kept'].map(lambda v: str(v).strip().lower() in ('true', '1', 'yes'))
    fish = fish[kept].copy()
    fish = fish[fish['fish_species'].str.lower() == 'walleye'].reset_index(drop=True)
    fish['depth'] = pd.to_numeric(fish['depth'], errors='coerce') * -1   # flip sign
    fish['length'] = pd.to_numeric(fish['length'], errors='coerce')
    fish['day'] = fish['datetime'].dt.day_name()                        # re-derived
    fish['measured_wt_lbs'] = (pd.to_numeric(raw.get('measured_wt_lbs'), errors='coerce')
                               if 'measured_wt_lbs' in raw.columns else np.nan)

    # --- daily anchor: group by weigh_session_id, filter on daily_wt_lbs ----------
    if not daily.empty:
        for c in ('daily_wt_lbs', 'day_inches', 'daily_wt_per_inch'):
            if c in daily.columns:
                daily[c] = pd.to_numeric(daily[c], errors='coerce')
        daily = (daily.drop_duplicates(subset='weigh_session_id')
                      .loc[daily['daily_wt_lbs'].notna()].copy())
        daily['weigh_date'] = pd.to_datetime(daily['weigh_date'])
        daily['year'] = daily['weigh_date'].dt.year

        # NET-TARE reconciliation: subtract the configured per-session net weight
        # from the measured bag for listed years, BEFORE any wt/inch is computed.
        # Inert while NET_TARE_LBS_BY_YEAR is empty (the default). Clamp at >=0.
        tare = daily['year'].map(NET_TARE_LBS_BY_YEAR).fillna(0.0)
        daily['daily_wt_lbs'] = (daily['daily_wt_lbs'] - tare).clip(lower=0.0)

        # DERIVE day_inches where blank (e.g. 2026 sessions logged with no inches):
        # use the sum of length over the KEPT WALLEYE catches in that session (the
        # `fish` frame above is already kept-walleye-only). Historical years already
        # carry a real day_inches and are left untouched.
        inches_by_session = (fish.groupby('weigh_session_id')['length'].sum()
                             if not fish.empty else pd.Series(dtype=float))
        derived = daily['weigh_session_id'].map(inches_by_session)
        daily['day_inches'] = daily['day_inches'].where(
            daily['day_inches'].notna(), derived)

        # Recompute wt/inch consistently from the (possibly tare-adjusted) bag and
        # the (possibly derived) inches, so measured & modeled share one bag basis.
        daily['daily_wt_per_inch'] = daily['daily_wt_lbs'] / daily['day_inches']
        daily = daily.reset_index(drop=True)
    return fish, daily


def fit_length_weight(fish, min_n=MIN_FIT_N):
    """Fit W = a * L**b by OLS on log-log if enough individual weights exist.
    Returns dict(a, b, n, r2) or None."""
    if 'measured_wt_lbs' not in fish:
        return None
    s = fish.dropna(subset=['measured_wt_lbs', 'length'])
    s = s[(s['measured_wt_lbs'] > 0) & (s['length'] > 0)]
    if len(s) < min_n:
        return None
    x, y = np.log(s['length'].values), np.log(s['measured_wt_lbs'].values)
    b, log_a = np.polyfit(x, y, 1)
    r2 = 1 - np.sum((y - (log_a + b * x)) ** 2) / np.sum((y - y.mean()) ** 2)
    return dict(a=float(np.exp(log_a)), b=float(b), n=int(len(s)), r2=float(r2))


def estimate_weights(fish, daily, b):
    """Add calibrated power-law weight (`weight_est`) and relative weight
    (`rel_weight`). `a` is calibrated per weigh session to the measured daily bag.

    Grouping key: ``weigh_session_id`` when present on BOTH frames (NEW schema /
    ``load_history()``), else the normalized ``weigh_date`` (legacy ``load_data()``).
    """
    if 'weigh_session_id' in fish.columns and 'weigh_session_id' in daily.columns:
        day_key = fish['weigh_session_id']
        bag_by_day = dict(zip(daily['weigh_session_id'], daily['daily_wt_lbs']))
    else:
        day_key = fish['weigh_date'].dt.normalize()
        bag_by_day = dict(zip(daily['weigh_date'].dt.normalize(), daily['daily_wt_lbs']))

    den = sum(np.sum(g['length'].values ** b)
              for d, g in fish.groupby(day_key) if d in bag_by_day)
    pooled_a = daily['daily_wt_lbs'].sum() / den

    a_by_day = {d: (bag_by_day[d] / np.sum(g['length'].values ** b)
                    if d in bag_by_day else pooled_a)
                for d, g in fish.groupby(day_key)}

    fish['weight_est'] = day_key.map(a_by_day) * fish['length'] ** b
    ws = 10 ** WS_INTERCEPT * fish['length'] ** 3.180
    fish['rel_weight'] = 100 * fish['weight_est'] / ws
    return fish


# ---------------------------------------------------------------------------
# Load + estimate
# ---------------------------------------------------------------------------
fishing_data, daily_weights = load_data()

fit = fit_length_weight(fishing_data)
B_USED = fit['b'] if fit else B_LITERATURE
print(f"Exponent in use: b={B_USED:.3f} "
      + (f"(fitted from {fit['n']} individual weights, R^2={fit['r2']:.3f})"
         if fit else f"(literature default; <{MIN_FIT_N} individual weights logged)"))

fishing_data = estimate_weights(fishing_data, daily_weights, B_USED)

# Time-of-day analysis (pooled across years)
fishing_data['hour'] = fishing_data['datetime'].dt.hour
time_group = fishing_data.groupby('hour').agg(
    number_of_fish=('id', 'count'),
    average_size=('length', 'mean'),
).reset_index()

# Per-year comparison using the calibrated weight estimate
year_group = fishing_data.groupby('year').agg(
    number_of_fish=('id', 'count'),
    average_size=('length', 'mean'),
    total_weight_lbs=('weight_est', 'sum'),
    mean_rel_weight=('rel_weight', 'mean'),
).reset_index()

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------
fig = make_subplots(
    rows=3, cols=1,
    subplot_titles=(
        "Depth vs. Length (Violin + Sized Points)",
        "Time of Day vs. Number and Size of Fish",
        "Per-Year Comparison (Number of Fish & Total Weight)",
    ),
)

# Row 1: depth analysis with violin plot
fig.add_trace(
    go.Violin(y=fishing_data['depth'], x=fishing_data['length'], name='Fish by Depth',
              points='all', box_visible=True, meanline_visible=True, pointpos=0,
              orientation='h', scalemode='count'),
    row=1, col=1
)
fig.add_trace(
    go.Scatter(x=fishing_data['length'], y=fishing_data['depth'], mode='markers',
               marker=dict(size=fishing_data['length'], sizemode='diameter', sizeref=0.5),
               name='Fish Sizes'),
    row=1, col=1
)

# Row 2: time-of-day analysis
fig.add_trace(
    go.Bar(x=time_group['hour'], y=time_group['number_of_fish'], name='Number of Fish (by hour)'),
    row=2, col=1
)
fig.add_trace(
    go.Scatter(x=time_group['hour'], y=time_group['average_size'], name='Avg Size (by hour)',
               mode='lines+markers'),
    row=2, col=1
)

# Row 3: per-year comparison (count + total estimated weight)
fig.add_trace(
    go.Bar(x=year_group['year'], y=year_group['number_of_fish'], name='Number of Fish (by year)'),
    row=3, col=1
)
fig.add_trace(
    go.Scatter(x=year_group['year'], y=year_group['total_weight_lbs'], name='Total Weight lbs (by year)',
               mode='lines+markers'),
    row=3, col=1
)
fig.update_xaxes(title_text="Year", dtick=1, row=3, col=1)

fig.update_layout(height=1100, showlegend=True, title_text="Fishing Trip Analysis Dashboard")
fig.show()
