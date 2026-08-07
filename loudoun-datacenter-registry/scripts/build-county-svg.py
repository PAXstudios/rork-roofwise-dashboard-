#!/usr/bin/env python3
"""
Build the Loudoun County map graphic used in the site's branding.

Reads data/districts.geojson (produced by refresh-facilities.py) and emits:

    data/county.json          district paths + the projection constants, so
                              js/hero-map.js can place facility points in the
                              same coordinate space at runtime
    assets/loudoun-mark.svg   heavily simplified county silhouette for the
                              header logo and the favicon

Standard library only. Run after refresh-facilities.py, or any time the county
redraws its district boundaries:

    python3 scripts/build-county-svg.py
"""

from __future__ import annotations

import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
ASSETS = os.path.join(ROOT, "assets")

# SVG canvas. Width is chosen; height falls out of the county's aspect ratio.
CANVAS_WIDTH = 1000.0
PADDING = 8.0


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------


def rings_of(geometry: dict) -> list[list[list[float]]]:
    """Exterior ring of each polygon, for Polygon or MultiPolygon."""
    if not geometry:
        return []
    kind = geometry.get("type")
    coords = geometry.get("coordinates") or []
    if kind == "Polygon":
        return [coords[0]] if coords else []
    if kind == "MultiPolygon":
        return [poly[0] for poly in coords if poly]
    return []


def simplify(ring: list[list[float]], tolerance: float) -> list[list[float]]:
    """Douglas-Peucker, iterative so a dense ring can't blow the stack."""
    if len(ring) < 3:
        return ring

    keep = [False] * len(ring)
    keep[0] = keep[-1] = True
    stack = [(0, len(ring) - 1)]

    while stack:
        start, end = stack.pop()
        if end <= start + 1:
            continue
        x0, y0 = ring[start]
        x1, y1 = ring[end]
        dx, dy = x1 - x0, y1 - y0
        denom = math.hypot(dx, dy)

        far_index, far_dist = -1, tolerance
        for i in range(start + 1, end):
            px, py = ring[i]
            if denom == 0:
                dist = math.hypot(px - x0, py - y0)
            else:
                dist = abs(dy * px - dx * py + x1 * y0 - y1 * x0) / denom
            if dist > far_dist:
                far_dist, far_index = dist, i

        if far_index != -1:
            keep[far_index] = True
            stack.append((start, far_index))
            stack.append((far_index, end))

    return [pt for pt, k in zip(ring, keep) if k]


def ring_area(ring: list[list[float]]) -> float:
    """Absolute shoelace area — used to find each district's biggest piece."""
    total = 0.0
    for i in range(len(ring) - 1):
        total += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1]
    return abs(total / 2.0)


def county_outline(features: list[dict]) -> list[list[list[float]]]:
    """The county's true outer boundary, as closed rings.

    The eight districts tile the county exactly and — verified against this
    dataset — adjacent districts share identical vertices. So every interior
    edge appears in exactly two districts and every boundary edge appears in
    exactly one. Keeping the singletons and chaining them gives one clean
    silhouette, which is what the logo needs; drawing all eight district shapes
    on top of each other instead leaves hairline gaps along the shared seams.
    """
    edge_count: dict[tuple, int] = {}
    for feature in features:
        for ring in rings_of(feature.get("geometry")):
            for i in range(len(ring) - 1):
                a, b = tuple(ring[i]), tuple(ring[i + 1])
                key = (a, b) if a < b else (b, a)
                edge_count[key] = edge_count.get(key, 0) + 1

    # Walk EDGES, not vertices. A vertex where three boundary segments meet —
    # which happens wherever a district corner touches the county edge — would
    # stop a vertex-based walk dead and shatter the outline into fragments.
    boundary = [edge for edge, count in edge_count.items() if count == 1]

    incident: dict[tuple, list[int]] = {}
    for index, (a, b) in enumerate(boundary):
        incident.setdefault(a, []).append(index)
        incident.setdefault(b, []).append(index)

    used = [False] * len(boundary)
    outline: list[list[list[float]]] = []

    def pick_next(current: tuple, previous: tuple) -> tuple | None:
        """Choose the straightest unused continuation.

        Most boundary vertices have exactly two edges and this is trivial. About
        25 of them are degree-4 pinch points, where the county edge touches
        itself because district corners meet on the boundary. Taking an
        arbitrary branch there produces spurs and shatters the ring, so follow
        the edge that deviates least from the incoming direction.
        """
        options = []
        for index in incident.get(current, []):
            if used[index]:
                continue
            a, b = boundary[index]
            other = b if a == current else a
            options.append((index, other))

        if not options:
            return None
        if len(options) == 1:
            used[options[0][0]] = True
            return options[0][1]

        in_angle = math.atan2(current[1] - previous[1], current[0] - previous[0])
        best = None
        for index, other in options:
            out_angle = math.atan2(other[1] - current[1], other[0] - current[0])
            turn = abs((out_angle - in_angle + math.pi) % (2 * math.pi) - math.pi)
            if best is None or turn < best[0]:
                best = (turn, index, other)

        used[best[1]] = True
        return best[2]

    for seed in range(len(boundary)):
        if used[seed]:
            continue

        used[seed] = True
        start, current = boundary[seed]
        ring = [start, current]
        previous = start

        while current != start:
            nxt = pick_next(current, previous)
            if nxt is None:
                break  # open chain; shouldn't happen on a clean tiling
            ring.append(nxt)
            previous, current = current, nxt

        if len(ring) >= 4:
            if ring[0] != ring[-1]:
                ring.append(ring[0])
            outline.append([list(p) for p in ring])

    # Tracing through the pinch points also spins off ~40 microscopic slivers
    # where the boundary doubles back on itself. The county proper is 99.99% of
    # the traced area, so anything under 1% is noise, not an island.
    if not outline:
        return []

    total = sum(ring_area(ring) for ring in outline)
    return [ring for ring in outline if ring_area(ring) > total * 0.01]


# ---------------------------------------------------------------------------
# Projection
# ---------------------------------------------------------------------------


class Projection:
    """Equirectangular with a cos(lat) correction on x.

    At Loudoun's latitude a degree of longitude is only ~0.777 of a degree of
    latitude, so projecting raw lng/lat would squash the county noticeably.
    The correction is applied at the bbox's centre latitude, which is accurate
    enough across a span this small and keeps the maths invertible in JS.
    """

    def __init__(self, min_lng, min_lat, max_lng, max_lat):
        self.min_lng = min_lng
        self.min_lat = min_lat
        self.max_lat = max_lat
        self.cos_lat = math.cos(math.radians((min_lat + max_lat) / 2.0))

        span_x = (max_lng - min_lng) * self.cos_lat
        span_y = max_lat - min_lat

        self.scale = (CANVAS_WIDTH - 2 * PADDING) / span_x
        self.height = span_y * self.scale + 2 * PADDING

    def point(self, lng: float, lat: float) -> tuple[float, float]:
        x = (lng - self.min_lng) * self.cos_lat * self.scale + PADDING
        # SVG y grows downward; latitude grows upward.
        y = (self.max_lat - lat) * self.scale + PADDING
        return x, y

    def as_dict(self) -> dict:
        return {
            "minLng": round(self.min_lng, 6),
            "maxLat": round(self.max_lat, 6),
            "cosLat": round(self.cos_lat, 6),
            "scale": round(self.scale, 4),
            "padding": PADDING,
        }


def path_from_rings(rings, projection, precision=1) -> str:
    """One SVG path 'd' string covering every ring of a district."""
    parts = []
    for ring in rings:
        if len(ring) < 3:
            continue
        commands = []
        for index, (lng, lat) in enumerate(ring):
            x, y = projection.point(lng, lat)
            commands.append(
                ("M" if index == 0 else "L") + f"{x:.{precision}f} {y:.{precision}f}"
            )
        parts.append("".join(commands) + "Z")
    return "".join(parts)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    source = os.path.join(DATA, "districts.geojson")
    if not os.path.exists(source):
        print(
            f"error: {source} not found. Run scripts/refresh-facilities.py first.",
            file=sys.stderr,
        )
        return 1

    with open(source, encoding="utf-8") as handle:
        geojson = json.load(handle)

    features = geojson.get("features", [])
    if not features:
        print("error: districts.geojson has no features", file=sys.stderr)
        return 1

    # ---- Projection from the full county bbox ------------------------------
    lngs, lats = [], []
    for feature in features:
        for ring in rings_of(feature.get("geometry")):
            for lng, lat in ring:
                lngs.append(lng)
                lats.append(lat)

    projection = Projection(min(lngs), min(lats), max(lngs), max(lats))
    view_box = f"0 0 {CANVAS_WIDTH:.0f} {projection.height:.0f}"

    # ---- Detailed district paths for the hero ------------------------------
    districts = []
    for feature in features:
        name = (feature.get("properties") or {}).get("name")
        rings = rings_of(feature.get("geometry"))
        if not name or not rings:
            continue

        # Light simplification: the hero renders at ~1000px wide, so sub-pixel
        # detail is wasted bytes. 0.0004 deg is roughly 35 m.
        reduced = [simplify(ring, 0.0004) for ring in rings]
        reduced = [ring for ring in reduced if len(ring) >= 3]

        biggest = max(reduced, key=ring_area)
        centre_lng = sum(p[0] for p in biggest) / len(biggest)
        centre_lat = sum(p[1] for p in biggest) / len(biggest)
        label_x, label_y = projection.point(centre_lng, centre_lat)

        districts.append(
            {
                "name": name,
                "d": path_from_rings(reduced, projection),
                "labelX": round(label_x, 1),
                "labelY": round(label_y, 1),
                "population2020": (feature.get("properties") or {}).get("population_2020"),
            }
        )

    districts.sort(key=lambda d: d["name"])

    county = {
        "viewBox": view_box,
        "width": CANVAS_WIDTH,
        "height": round(projection.height, 1),
        "projection": projection.as_dict(),
        "districts": districts,
    }

    county_path = os.path.join(DATA, "county.json")
    with open(county_path, "w", encoding="utf-8") as handle:
        json.dump(county, handle, separators=(",", ":"))
        handle.write("\n")

    # ---- Silhouette for the logo mark --------------------------------------
    # A single true outline, not eight stacked district shapes. Simplified to
    # 0.0015 deg (~130 m), which is invisible at logo size but keeps the
    # distinctive corners — the Potomac along the north-east and the straight
    # diagonal down the south-west are what make the shape recognisable.
    os.makedirs(ASSETS, exist_ok=True)

    outline = county_outline(features)
    if not outline:
        print("error: could not derive a county outline", file=sys.stderr)
        return 1

    outline = [simplify(ring, 0.0015) for ring in outline]
    outline = [ring for ring in outline if len(ring) >= 4]
    outline.sort(key=ring_area, reverse=True)

    mark_projection = Projection(min(lngs), min(lats), max(lngs), max(lats))
    mark_paths = path_from_rings(outline, mark_projection, precision=0)

    mark_svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}" '
        f'role="img" aria-label="Outline map of Loudoun County, Virginia">'
        f'<path d="{mark_paths}" fill="currentColor" fill-rule="evenodd"/>'
        f"</svg>\n"
    )

    mark_path = os.path.join(ASSETS, "loudoun-mark.svg")
    with open(mark_path, "w", encoding="utf-8") as handle:
        handle.write(mark_svg)

    # The county outline is also useful to the hero, which strokes it as a
    # single continuous line rather than eight district edges.
    county["outline"] = path_from_rings(
        [simplify(ring, 0.0004) for ring in county_outline(features)], projection
    )
    with open(county_path, "w", encoding="utf-8") as handle:
        json.dump(county, handle, separators=(",", ":"))
        handle.write("\n")

    print(f"  data/county.json           {os.path.getsize(county_path) / 1024:6.1f} KB")
    print(f"  assets/loudoun-mark.svg    {os.path.getsize(mark_path) / 1024:6.1f} KB")
    print(f"\nviewBox {view_box} · {len(districts)} districts")
    for district in districts:
        print(f"  {district['name']:<14} {len(district['d']):>6} path chars")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - top-level CLI guard
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
