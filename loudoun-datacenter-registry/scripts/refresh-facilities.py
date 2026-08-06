#!/usr/bin/env python3
"""
Refresh the Loudoun County data center facility layers used by the map.

Pulls four public ArcGIS FeatureServer / MapServer layers published by Loudoun
County GIS and writes normalized GeoJSON into ../data/. Standard library only —
no pip installs, no build step.

Usage:
    python3 scripts/refresh-facilities.py

Outputs (all relative to the project root):
    data/facilities.geojson        Point per data center parcel, normalized status
    data/facility-outlines.geojson Simplified parcel polygons, for the overlay
    data/districts.geojson         Election district boundaries
    data/localities.json           District list + population + facility counts
    data/PROVENANCE.md             Where every field came from and when

The county refreshes the underlying parcel data roughly every six months, so
re-running this a couple of times a year is enough.
"""

from __future__ import annotations

import json
import math
import os
import sys
import urllib.parse
import urllib.request
from datetime import date

# --------------------------------------------------------------------------
# Sources
# --------------------------------------------------------------------------

AGOL = "https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services"
LOGIS = "https://logis.loudoun.gov/gis/rest/services"

SOURCES = {
    "existing": f"{AGOL}/Existing_Data_Center_Parcel/FeatureServer/1",
    "pipeline": f"{AGOL}/Pipeline_Data_Center_Areas/FeatureServer/1",
    "buildings": f"{AGOL}/Data_Center_Building_Outlines/FeatureServer/0",
    "districts": f"{LOGIS}/COL/ElectionDistricts/MapServer/8",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")

USER_AGENT = "loudoun-datacenter-watch/1.0 (+https://github.com/PAXstudios)"

# Loudoun County bounding box, used to sanity-check every geometry we keep.
BBOX = (-78.05, 38.80, -77.20, 39.35)  # west, south, east, north


# --------------------------------------------------------------------------
# Fetching
# --------------------------------------------------------------------------


def fetch_geojson(layer_url: str, out_fields: str = "*") -> dict:
    """Query an ArcGIS layer for all features as GeoJSON in WGS84."""
    params = urllib.parse.urlencode(
        {
            "where": "1=1",
            "outFields": out_fields,
            "outSR": "4326",
            "f": "geojson",
        }
    )
    url = f"{layer_url}/query?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        payload = json.load(resp)
    if "error" in payload:
        raise RuntimeError(f"{layer_url} returned {payload['error']}")
    features = payload.get("features") or []
    if not features:
        raise RuntimeError(f"{layer_url} returned zero features")
    return payload


# --------------------------------------------------------------------------
# Geometry helpers
# --------------------------------------------------------------------------


def rings_of(geometry: dict) -> list[list[list[float]]]:
    """Return every polygon's exterior ring, for Polygon or MultiPolygon."""
    if not geometry:
        return []
    kind = geometry.get("type")
    coords = geometry.get("coordinates") or []
    if kind == "Polygon":
        return [coords[0]] if coords else []
    if kind == "MultiPolygon":
        return [poly[0] for poly in coords if poly]
    return []


def ring_area_centroid(ring: list[list[float]]) -> tuple[float, float, float]:
    """Signed area and area-weighted centroid of a closed ring."""
    area2 = 0.0
    cx = 0.0
    cy = 0.0
    for i in range(len(ring) - 1):
        x0, y0 = ring[i][0], ring[i][1]
        x1, y1 = ring[i + 1][0], ring[i + 1][1]
        cross = x0 * y1 - x1 * y0
        area2 += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if abs(area2) < 1e-12:
        # Degenerate ring — fall back to the mean vertex.
        n = max(len(ring), 1)
        return (
            0.0,
            sum(p[0] for p in ring) / n,
            sum(p[1] for p in ring) / n,
        )
    return abs(area2 / 2.0), cx / (3.0 * area2), cy / (3.0 * area2)


def centroid_of(geometry: dict) -> tuple[float, float] | None:
    """Centroid of the largest ring in a (multi)polygon."""
    best = None
    for ring in rings_of(geometry):
        if len(ring) < 4:
            continue
        area, cx, cy = ring_area_centroid(ring)
        if best is None or area > best[0]:
            best = (area, cx, cy)
    if best is None:
        return None
    return best[1], best[2]


def in_bbox(lng: float, lat: float) -> bool:
    west, south, east, north = BBOX
    return west <= lng <= east and south <= lat <= north


def point_in_ring(lng: float, lat: float, ring: list[list[float]]) -> bool:
    """Ray-casting point-in-polygon test."""
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > lat) != (yj > lat):
            x_cross = (xj - xi) * (lat - yi) / (yj - yi) + xi
            if lng < x_cross:
                inside = not inside
        j = i
    return inside


def simplify(ring: list[list[float]], tolerance: float) -> list[list[float]]:
    """Douglas-Peucker, iterative so deep rings can't blow the stack."""
    if len(ring) < 3:
        return ring

    keep = [False] * len(ring)
    keep[0] = keep[-1] = True
    stack = [(0, len(ring) - 1)]

    while stack:
        start, end = stack.pop()
        if end <= start + 1:
            continue
        x0, y0 = ring[start][0], ring[start][1]
        x1, y1 = ring[end][0], ring[end][1]
        dx, dy = x1 - x0, y1 - y0
        denom = math.hypot(dx, dy)

        far_index = -1
        far_dist = tolerance
        for i in range(start + 1, end):
            px, py = ring[i][0], ring[i][1]
            if denom == 0:
                dist = math.hypot(px - x0, py - y0)
            else:
                dist = abs(dy * px - dx * py + x1 * y0 - y1 * x0) / denom
            if dist > far_dist:
                far_dist = dist
                far_index = i

        if far_index != -1:
            keep[far_index] = True
            stack.append((start, far_index))
            stack.append((far_index, end))

    return [pt for pt, k in zip(ring, keep) if k]


def round_ring(ring: list[list[float]], precision: int) -> list[list[float]]:
    return [[round(p[0], precision), round(p[1], precision)] for p in ring]


def simplify_geometry(geometry: dict, tolerance: float, precision: int) -> dict | None:
    """Simplify + round a (multi)polygon, dropping rings that collapse."""
    out_polys = []
    for ring in rings_of(geometry):
        reduced = round_ring(simplify(ring, tolerance), precision)
        # Re-close the ring; simplification can drop the duplicate last point.
        if len(reduced) >= 3 and reduced[0] != reduced[-1]:
            reduced.append(reduced[0])
        if len(reduced) >= 4:
            out_polys.append([reduced])
    if not out_polys:
        return None
    if len(out_polys) == 1:
        return {"type": "Polygon", "coordinates": out_polys[0]}
    return {"type": "MultiPolygon", "coordinates": out_polys}


# --------------------------------------------------------------------------
# Normalization
# --------------------------------------------------------------------------


def clean(value) -> str | None:
    """Trim a county string field; treat blanks and 'N/A' as missing."""
    if value is None:
        return None
    text = str(value).strip()
    if not text or text.upper() in {"N/A", "NA", "NULL", "NONE", "<NULL>"}:
        return None
    return text


# Tokens that must stay upper-case when we un-SHOUT the county's text. An
# allowlist, not a length rule — a length rule turns "BROAD RUN" into "Broad RUN".
KEEP_UPPER = {
    "LLC", "LLP", "LP", "LC", "PLC", "JV", "GP", "REIT",
    "DC", "US", "USA", "VA", "NV", "SA", "AWS", "QTS", "NTT", "IAD", "BOS",
    "II", "III", "IV", "VI", "VII", "VIII", "IX",
}

# Lower-cased inside a name, but never as the first word.
KEEP_LOWER = {"of", "the", "at", "and", "for", "on", "in", "a", "an", "to"}


def title_case(value: str | None) -> str | None:
    """County data is SHOUTING. Make it readable without mangling initialisms.

    Words can carry leading punctuation ("(ASHBURN)"), so capitalize the first
    *letter* rather than the first character.
    """
    if not value:
        return None

    words = []
    for index, word in enumerate(value.split()):
        bare = word.strip("().,/\\-").upper()

        if bare in KEEP_UPPER:
            words.append(word.upper())
            continue
        if any(ch.isdigit() for ch in word):
            # Parcel refs and phase numbers ("DC-2", "PH1") stay as-is.
            words.append(word.upper())
            continue
        if index > 0 and bare.lower() in KEEP_LOWER:
            words.append(word.lower())
            continue

        lowered = word.lower()
        for position, char in enumerate(lowered):
            if char.isalpha():
                words.append(lowered[:position] + char.upper() + lowered[position + 1:])
                break
        else:
            words.append(word)

    return " ".join(words)


def normalize_built_status(raw: str | None) -> str:
    """Map the county's Built_Status text onto our three public statuses.

    The source data contains a typo ('BULT/UNDER CONSTRUCTION') on one record,
    so match loosely rather than against an exact set.
    """
    text = (raw or "").upper()
    if "UNDER CONSTRUCTION" in text:
        return "under_construction"
    if "BUILT" in text:
        return "operational"
    return "unknown"


def build_district_index(districts_geojson: dict) -> list[tuple[str, list[list[list[float]]]]]:
    index = []
    for feature in districts_geojson.get("features", []):
        name = clean(feature.get("properties", {}).get("EL_NAME"))
        rings = rings_of(feature.get("geometry") or {})
        if name and rings:
            index.append((title_case(name), rings))
    return index


def district_for(lng: float, lat: float, index) -> str | None:
    for name, rings in index:
        for ring in rings:
            if point_in_ring(lng, lat, ring):
                return name
    return None


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------


def main() -> int:
    os.makedirs(DATA, exist_ok=True)

    print("Fetching Loudoun County GIS layers...")
    raw = {}
    for key, url in SOURCES.items():
        fields = "Name" if key == "buildings" else "*"
        print(f"  {key:<10} {url}")
        raw[key] = fetch_geojson(url, fields)
        print(f"             {len(raw[key]['features'])} features")

    district_index = build_district_index(raw["districts"])
    print(f"\nIndexed {len(district_index)} election districts")

    facilities = []
    outlines = []
    skipped = 0
    counter = 0

    # ---- Existing (built / under construction) parcels ---------------------
    for feature in raw["existing"]["features"]:
        props = feature.get("properties", {})
        geometry = feature.get("geometry")
        center = centroid_of(geometry or {})
        if not center or not in_bbox(*center):
            skipped += 1
            continue

        lng, lat = center
        counter += 1
        fid = f"lc-ex-{counter:03d}"

        district = title_case(clean(props.get("ELECTION_DISTRICT"))) or district_for(
            lng, lat, district_index
        )
        status = normalize_built_status(clean(props.get("Built_Status")))
        project = title_case(clean(props.get("Project")))
        operator = title_case(clean(props.get("Owner")))

        facilities.append(
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [round(lng, 6), round(lat, 6)]},
                "properties": {
                    "id": fid,
                    "name": project or operator or "Unnamed data center parcel",
                    "operator": operator,
                    "status": status,
                    "status_raw": clean(props.get("Built_Status")),
                    "district": district,
                    "sqft": props.get("Overall_SQ_FT") or None,
                    "acres": round(props["PA_GIS_ACRE"], 2)
                    if isinstance(props.get("PA_GIS_ACRE"), (int, float))
                    else None,
                    "zoning": clean(props.get("ZONING")),
                    "zoning_case": clean(props.get("Zoning_Case_Number")),
                    "parcel_id": clean(props.get("PA_MCPI")),
                    "policy_area": title_case(clean(props.get("POLICY_AREA"))),
                    "source": "Loudoun County GIS — Existing Data Center Parcels",
                },
            }
        )

        shape = simplify_geometry(geometry or {}, tolerance=0.00004, precision=5)
        if shape:
            outlines.append(
                {
                    "type": "Feature",
                    "geometry": shape,
                    "properties": {"id": fid, "status": status},
                }
            )

    # ---- Pipeline (proposed / approved but not built) parcels --------------
    for feature in raw["pipeline"]["features"]:
        props = feature.get("properties", {})
        geometry = feature.get("geometry")
        center = centroid_of(geometry or {})
        if not center or not in_bbox(*center):
            skipped += 1
            continue

        lng, lat = center
        counter += 1
        fid = f"lc-pl-{counter:03d}"

        subdivision = title_case(clean(props.get("FIRST_Subdivision")))
        application = clean(props.get("Application"))

        facilities.append(
            {
                "type": "Feature",
                "geometry": {"type": "Point", "coordinates": [round(lng, 6), round(lat, 6)]},
                "properties": {
                    "id": fid,
                    "name": subdivision or application or "Proposed data center",
                    "operator": None,
                    "status": "proposed",
                    "status_raw": clean(props.get("FIRST_Status")),
                    "district": district_for(lng, lat, district_index),
                    "sqft": props.get("FIRST_Overall_SQ_FT") or None,
                    "acres": round(props["SUM_Pipeline_Acres"], 2)
                    if isinstance(props.get("SUM_Pipeline_Acres"), (int, float))
                    else None,
                    "zoning": None,
                    "zoning_case": clean(props.get("FIRST_Zoning_Case_Num")),
                    "application": application,
                    "source": "Loudoun County GIS — Data Center Pipeline Areas",
                },
            }
        )

        shape = simplify_geometry(geometry or {}, tolerance=0.00004, precision=5)
        if shape:
            outlines.append(
                {
                    "type": "Feature",
                    "geometry": shape,
                    "properties": {"id": fid, "status": "proposed"},
                }
            )

    # ---- Building footprints ----------------------------------------------
    buildings = []
    for feature in raw["buildings"]["features"]:
        shape = simplify_geometry(feature.get("geometry") or {}, tolerance=0.00002, precision=5)
        if shape:
            buildings.append(
                {"type": "Feature", "geometry": shape, "properties": {"kind": "building"}}
            )

    # ---- Election district boundaries --------------------------------------
    district_features = []
    for feature in raw["districts"]["features"]:
        props = feature.get("properties", {})
        name = title_case(clean(props.get("EL_NAME")))
        shape = simplify_geometry(feature.get("geometry") or {}, tolerance=0.0002, precision=5)
        if name and shape:
            district_features.append(
                {
                    "type": "Feature",
                    "geometry": shape,
                    "properties": {
                        "name": name,
                        "population_2020": props.get("EL_POP2020"),
                        "housing_units_2020": props.get("EL_HUNIT2020"),
                    },
                }
            )

    # ---- Locality summary --------------------------------------------------
    counts: dict[str, dict] = {}
    for feature in facilities:
        props = feature["properties"]
        name = props.get("district") or "Unassigned"
        bucket = counts.setdefault(
            name, {"operational": 0, "under_construction": 0, "proposed": 0, "unknown": 0}
        )
        bucket[props["status"]] = bucket.get(props["status"], 0) + 1

    localities = []
    for feature in district_features:
        name = feature["properties"]["name"]
        bucket = counts.get(name, {})
        localities.append(
            {
                "name": name,
                "population_2020": feature["properties"]["population_2020"],
                "facilities": {
                    "operational": bucket.get("operational", 0),
                    "under_construction": bucket.get("under_construction", 0),
                    "proposed": bucket.get("proposed", 0),
                    "total": sum(bucket.values()) if bucket else 0,
                },
            }
        )
    localities.sort(key=lambda d: -d["facilities"]["total"])

    generated = date.today().isoformat()

    def write(name: str, payload) -> None:
        path = os.path.join(DATA, name)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"))
            handle.write("\n")
        size = os.path.getsize(path) / 1024
        print(f"  {name:<28} {size:7.1f} KB")

    print("\nWriting data files:")
    write(
        "facilities.geojson",
        {
            "type": "FeatureCollection",
            "generated": generated,
            "source": "Loudoun County GIS",
            "features": facilities,
        },
    )
    write(
        "facility-outlines.geojson",
        {"type": "FeatureCollection", "generated": generated, "features": outlines},
    )
    write(
        "facility-buildings.geojson",
        {"type": "FeatureCollection", "generated": generated, "features": buildings},
    )
    write(
        "districts.geojson",
        {"type": "FeatureCollection", "generated": generated, "features": district_features},
    )
    write("localities.json", {"generated": generated, "districts": localities})

    totals = {"operational": 0, "under_construction": 0, "proposed": 0, "unknown": 0}
    total_sqft = 0
    for feature in facilities:
        props = feature["properties"]
        totals[props["status"]] += 1
        if isinstance(props.get("sqft"), (int, float)):
            total_sqft += props["sqft"]

    write(
        "summary.json",
        {
            "generated": generated,
            "counts": totals,
            "total": len(facilities),
            "total_sqft": total_sqft,
            "buildings": len(buildings),
            "districts": len(district_features),
        },
    )

    with open(os.path.join(DATA, "PROVENANCE.md"), "w", encoding="utf-8") as handle:
        handle.write(PROVENANCE_TEMPLATE.format(generated=generated, totals=totals,
                                                total=len(facilities),
                                                buildings=len(buildings)))
    print(f"  {'PROVENANCE.md':<28}")

    print(
        f"\nDone. {len(facilities)} facilities "
        f"({totals['operational']} operational, "
        f"{totals['under_construction']} under construction, "
        f"{totals['proposed']} proposed), "
        f"{len(buildings)} building footprints, {skipped} skipped."
    )
    return 0


PROVENANCE_TEMPLATE = """# Data provenance

Generated {generated} by `scripts/refresh-facilities.py`.

All facility data on this site comes from **Loudoun County GIS**, published as
public, unauthenticated ArcGIS services. Nothing here is scraped, guessed, or
hand-entered, and none of it is our own assessment of any facility.

## Sources

| File | Source layer | Publisher |
|---|---|---|
| `facilities.geojson` (operational, under construction) | [`Existing_Data_Center_Parcel/FeatureServer/1`](https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services/Existing_Data_Center_Parcel/FeatureServer/1) | Loudoun County GIS |
| `facilities.geojson` (proposed) | [`Pipeline_Data_Center_Areas/FeatureServer/1`](https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services/Pipeline_Data_Center_Areas/FeatureServer/1) | Loudoun County GIS |
| `facility-buildings.geojson` | [`Data_Center_Building_Outlines/FeatureServer/0`](https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services/Data_Center_Building_Outlines/FeatureServer/0) | Loudoun County GIS |
| `districts.geojson`, `localities.json` | [`COL/ElectionDistricts/MapServer/8`](https://logis.loudoun.gov/gis/rest/services/COL/ElectionDistricts/MapServer/8) | Loudoun County GIS |

Basemap tiles are © [OpenStreetMap](https://www.openstreetmap.org/copyright)
contributors, used under the Open Database License.

## What we changed

The raw county data is used as-is except for these mechanical transformations:

1. **Parcel polygons reduced to points.** Each parcel's map marker sits at the
   area-weighted centroid of its largest ring. The full polygons are kept in
   `facility-outlines.geojson` for the optional overlay.
2. **Status normalized.** The county's `Built_Status` field is mapped to three
   public statuses. `BUILT` becomes *operational*; anything containing
   `UNDER CONSTRUCTION` becomes *under construction*; every pipeline record
   becomes *proposed*. Note the source contains one typo'd value
   (`BULT/UNDER CONSTRUCTION`), which is why the match is substring-based.
   The original string is preserved in `status_raw`.
3. **Text title-cased.** County fields are stored in all caps. Short all-caps
   tokens (LLC, LP, DC, II) are left alone.
4. **Geometry simplified.** Douglas-Peucker at ~4 m tolerance, coordinates
   rounded to 5 decimal places, purely to keep the committed files small.
5. **Districts assigned by point-in-polygon** for pipeline records, which do not
   carry an election-district field. Existing parcels use the county's own
   `ELECTION_DISTRICT` value.

Records whose centroid falls outside the Loudoun County bounding box are dropped.

## Current snapshot

- {total} data center parcels: {totals[operational]} operational,
  {totals[under_construction]} under construction, {totals[proposed]} proposed
- {buildings} data center building footprints

## Refreshing

The county updates the parcel layers roughly every six months. To pull the
latest:

```bash
python3 scripts/refresh-facilities.py
```

It only needs Python 3.9+ and network access — no dependencies to install.
Review the diff before committing; a large unexpected change usually means the
county altered a field name rather than that 50 data centers appeared overnight.

## A note on facility ownership

The `operator` field is the property owner recorded in Loudoun County land
records. It is often a holding company rather than the brand operating the
facility, it can be out of date, and it does not establish who is responsible
for any condition a resident reports. Treat it as a pointer for further
research, not as an accusation.
"""


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - top-level CLI guard
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
