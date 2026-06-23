# fishing-analysis command front-end (INFRA-1 / HAY-119)
#
# Hybrid web stack: replay + analytics are generated static HTML; a single
# FastAPI file (server.py) serves ONLY the authoring tools. No DB; files are
# the source of truth. Python is managed by uv.

# Localhost-only host/port for the authoring server. Matches server.py defaults.
host := "127.0.0.1"
port := "8765"

# Default: list available recipes.
default:
    @just --list

# Render a replay for one day, e.g. `just replay 20260620`.
replay day:
    uv run --with pandas python replay_trip.py exports/2026/{{day}}

# Start the authoring server pointed at the area editor (GET /).
areas:
    @echo "Area editor:  http://{{host}}:{{port}}/  (POST/GET /areas)"
    uv run uvicorn server:app --host {{host}} --port {{port}}

# Start the same authoring server pointed at the trip-notes editor.
notes:
    @echo "Notes editor: http://{{host}}:{{port}}/notes  (POST/GET /notes?year=YYYY)"
    uv run uvicorn server:app --host {{host}} --port {{port}}

# Build analytics HTML if the builder exists (HAY-125), else degrade gracefully.
analytics:
    @if [ -f build_analytics.py ]; then \
        uv run --with pandas python build_analytics.py; \
    else \
        echo "analytics not built yet (HAY-125)"; \
    fi

# Ingest one day through the pipeline if it exists (HAY-131), else degrade.
ingest day:
    @if [ -f ingest.py ]; then \
        uv run --with pandas python ingest.py exports/2026/{{day}}; \
    elif [ -f pipeline.py ]; then \
        uv run --with pandas python pipeline.py exports/2026/{{day}}; \
    else \
        echo "ingest not built yet (HAY-131)"; \
    fi

# Benchmark a generated HTML page.
bench html:
    node tests/bench.js {{html}}

# Run the JS test harness and, if present, the Swift package tests.
test:
    node tests/harness.js
    @if [ -f app/FishingLoggerCore/Package.swift ]; then \
        swift test --package-path app/FishingLoggerCore; \
    else \
        echo "swift package tests not available"; \
    fi
