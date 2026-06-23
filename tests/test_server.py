"""Smoke test for server.py (INFRA-1 / HAY-119).

Run with:
    uv run --with httpx --with fastapi --with pytest pytest tests/test_server.py

This test points FISHING_DATA_ROOT at a temp dir BEFORE importing server, so it
never touches the real exports/ or areas/ on disk.
"""

import importlib
import json
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client(tmp_path, monkeypatch):
    # Point the output root at a throwaway tmp dir, then (re)import server so it
    # binds to that root. We also ensure the repo root is importable.
    repo_root = Path(__file__).resolve().parent.parent
    monkeypatch.setenv("FISHING_DATA_ROOT", str(tmp_path))
    if str(repo_root) not in sys.path:
        sys.path.insert(0, str(repo_root))
    sys.modules.pop("server", None)
    server = importlib.import_module("server")
    importlib.reload(server)
    with TestClient(server.app) as c:
        c._data_root = tmp_path  # stash for assertions
        yield c


def test_areas_round_trip(client, tmp_path):
    fc = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {"name": "Spring Creek"},
                "geometry": {"type": "Point", "coordinates": [-100.4, 45.0]},
            }
        ],
    }

    resp = client.post("/areas", json=fc)
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert payload["ok"] is True
    assert payload["count"] == 1

    written = tmp_path / "areas" / "areas.geojson"
    assert written.exists(), "areas.geojson was not written to the tmp root"
    on_disk = json.loads(written.read_text())
    assert on_disk["features"][0]["properties"]["name"] == "Spring Creek"

    got = client.get("/areas")
    assert got.status_code == 200
    assert got.json()["features"][0]["properties"]["name"] == "Spring Creek"


def test_areas_get_empty_when_absent(client):
    got = client.get("/areas")
    assert got.status_code == 200
    assert got.json() == {"type": "FeatureCollection", "features": []}


def test_areas_rejects_feature_without_name(client):
    bad = {
        "type": "FeatureCollection",
        "features": [{"type": "Feature", "properties": {}, "geometry": None}],
    }
    resp = client.post("/areas", json=bad)
    assert resp.status_code == 400


def test_areas_rejects_non_feature_collection(client):
    resp = client.post("/areas", json={"type": "Nope", "features": []})
    assert resp.status_code == 400


def test_notes_round_trip(client, tmp_path):
    body = {
        "trip": "2026-06",
        "review": "Best walleye bite of the year.",
        "days": {"20260620": {"notes": "Topwater at dawn."}},
    }

    resp = client.post("/notes", json=body)
    assert resp.status_code == 200, resp.text
    payload = resp.json()
    assert payload["ok"] is True
    assert payload["year"] == 2026

    written = tmp_path / "exports" / "2026" / "trip_notes.json"
    assert written.exists(), "trip_notes.json was not written to the tmp root"
    on_disk = json.loads(written.read_text())
    assert on_disk["days"]["20260620"]["notes"] == "Topwater at dawn."

    got = client.get("/notes", params={"year": 2026})
    assert got.status_code == 200
    assert got.json()["review"] == "Best walleye bite of the year."


def test_notes_get_empty_skeleton_when_absent(client):
    got = client.get("/notes", params={"year": 1999})
    assert got.status_code == 200
    assert got.json() == {"trip": None, "review": None, "days": {}}


def test_notes_rejects_bad_trip(client):
    resp = client.post("/notes", json={"trip": "notayear", "review": None, "days": {}})
    assert resp.status_code == 400


def test_index_serves_placeholder_when_no_html(client):
    # map-areas.html does not exist yet, so the placeholder lists the endpoints.
    resp = client.get("/")
    assert resp.status_code == 200
    assert "/areas" in resp.text
