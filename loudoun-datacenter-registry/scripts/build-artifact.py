#!/usr/bin/env python3
"""
Bundle the whole site into one self-contained HTML file.

    python3 scripts/build-artifact.py -o /tmp/watch.html

Why this exists: a Claude Artifact is a single page behind a strict
Content-Security-Policy that blocks every request to an external host. No CDN,
no separate stylesheet, no map tile server, no font file. So to show the real
site inside the app, everything it needs has to be inlined — CSS, fonts,
Leaflet, the county data, and a cache of map tiles as data URIs.

The result is the actual site, not a mock-up: the same CSS, the same map code,
the same 224 county parcels, the same watchlist rule, the same headlines. The
only differences are structural, and all of them are listed in ARTIFACT_NOTES
below so nobody mistakes the demo for the deployed thing.

Requires a tile cache on disk (see --tiles). Without one the map still works,
it just has no basemap under the markers.
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Kept to z12: z13 for the whole county is another 12 MB of tiles and the
# artifact has a 16 MB ceiling. Leaflet upsamples past maxNativeZoom, so
# zooming further still works, just softer.
TILE_ZOOMS = (10, 11, 12)
MAX_NATIVE_ZOOM = 12
MAX_ZOOM = 16

DATA_FILES = [
    "data/facilities.geojson",
    "data/districts.geojson",
    "data/facility-outlines.geojson",
    "data/facility-buildings.geojson",
    "data/county.json",
    "data/localities.json",
    "data/summary.json",
    "data/news-home.json",
]

CSS_FILES = ["css/tokens.css", "css/base.css", "css/components.css", "css/animations.css"]

# Order matters — these are plain scripts sharing a window.LDCW namespace.
JS_FILES = [
    "js/config.js",
    "js/schema.js",
    "js/local-store.js",
    "js/store.js",
    "js/ui.js",
    "js/motion.js",
    "js/map-layers.js",
    "js/map-tools.js",
    "js/map.js",
    "js/hero-timeline.js",
    "js/report-detail.js",
    "js/watchlist.js",
    "js/news.js",
]

# (file, family, style, weight range, width range or None)
FONTS = [
    ("archivo.woff2", "Archivo Variable", "normal", "100 900", "62% 125%"),
    ("archivo-italic.woff2", "Archivo Variable", "italic", "100 900", "62% 125%"),
    ("source-serif.woff2", "Source Serif Variable", "normal", "200 900", None),
    ("source-serif-italic.woff2", "Source Serif Variable", "italic", "200 900", None),
    ("plex-mono.woff2", "IBM Plex Mono", "normal", "400 600", None),
]


def read(path: str) -> str:
    with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        return handle.read()


def data_uri(path: str) -> str:
    mime = mimetypes.guess_type(path)[0] or "application/octet-stream"
    with open(path, "rb") as handle:
        return f"data:{mime};base64," + base64.b64encode(handle.read()).decode("ascii")


# --------------------------------------------------------------------------
# Tiles
# --------------------------------------------------------------------------


def collect_tiles(directory: str, mime: str) -> dict:
    """Read a {z}/{y}/{x} tile tree into {"z/y/x": data-uri}."""
    out = {}
    if not directory or not os.path.isdir(directory):
        return out
    for z in TILE_ZOOMS:
        zdir = os.path.join(directory, str(z))
        if not os.path.isdir(zdir):
            continue
        for y in os.listdir(zdir):
            ydir = os.path.join(zdir, y)
            if not os.path.isdir(ydir):
                continue
            for x in os.listdir(ydir):
                path = os.path.join(ydir, x)
                if os.path.getsize(path) < 400:
                    continue  # an error page, not imagery
                encoded = base64.b64encode(open(path, "rb").read()).decode("ascii")
                out[f"{z}/{y}/{x}"] = f"data:{mime};base64,{encoded}"
    return out


# --------------------------------------------------------------------------
# Page shell
# --------------------------------------------------------------------------

SECTIONS = [
    ("map", "Map"),
    ("reports", "Reports"),
    ("watchlist", "Watchlist"),
    ("news", "News"),
    ("stats", "Statistics"),
    ("about", "About"),
]

ARTIFACT_NOTES = """
<div class="banner banner--info demo-note">
  <p><strong>This is the real site, running inside Claude.</strong> Same code, same
  design, and the same 224 data center parcels pulled from Loudoun County GIS. Three things
  differ from a normal deployment, because an artifact cannot make any external request:</p>
  <ul>
    <li><strong>Map tiles are a built-in cache</strong> covering Loudoun at zoom 10&ndash;12.
      Zoom in past that and imagery goes soft; pan well outside the county and it runs out.</li>
    <li><strong>The community reports are illustrative samples</strong>, not real submissions
      &mdash; the same demo data the site ships with when no database is connected.</li>
    <li><strong>Submitting, photo upload and address search are switched off</strong>, since all
      three need a server.</li>
  </ul>
  <p>Everything else is live: the basemap switcher, parcel and district overlays, the heat
  layer, measure and radius tools, the watchlist rule, report detail with permalinks, and 420
  real headlines collected from public news feeds.</p>
</div>
"""


def build(tiles_sat: str, tiles_osm: str, news_limit: int) -> str:
    css = "\n".join(f"/* ---- {f} ---- */\n" + read(f) for f in CSS_FILES)

    font_css = []
    for filename, family, style, weight, width in FONTS:
        path = os.path.join(ROOT, "vendor", "fonts", filename)
        if not os.path.exists(path):
            continue
        # Plex Mono is a static face; declaring it as woff2-variations makes
        # some engines reject it outright and silently fall back.
        fmt = "woff2-variations" if width or "Variable" in family else "woff2"
        stretch = f"font-stretch:{width};" if width else ""
        font_css.append(
            f'@font-face{{font-family:"{family}";src:url("{data_uri(path)}") '
            f'format("{fmt}");font-weight:{weight};font-style:{style};{stretch}'
            "font-display:swap;}"
        )

    payload = {}
    for path in DATA_FILES:
        full = os.path.join(ROOT, path)
        if os.path.exists(full):
            payload[path] = json.loads(read(path))

    # The full archive is 220 KB and the demo shows the most recent slice.
    news = json.loads(read("data/news.json"))
    news["items"] = news["items"][:news_limit]
    news["count"] = len(news["items"])
    payload["data/news.json"] = news

    mark = read("assets/loudoun-mark.svg")

    satellite = collect_tiles(tiles_sat, "image/jpeg")
    streets = collect_tiles(tiles_osm, "image/png")

    leaflet_css = read("vendor/leaflet.css")
    # Leaflet's stylesheet points at sprite images for the zoom control and the
    # default marker; the CSP would block them. The site draws its own markers,
    # so the only real loss is the layers icon, which this build doesn't use.
    leaflet_css = re.sub(r"url\((?!data:)[^)]*\)", "none", leaflet_css)

    js = "\n".join(f"/* ---- {f} ---- */\n" + read(f) for f in JS_FILES)

    nav = "".join(
        f'<button type="button" class="site-nav__link artifact-tab'
        f'{" is-current" if key == "map" else ""}" data-section="{key}">{label}</button>'
        for key, label in SECTIONS
    )

    return PAGE.format(
        font_css="".join(font_css),
        leaflet_css=leaflet_css,
        markercluster_css=read("vendor/markercluster.css") + read("vendor/markercluster.default.css"),
        css=css,
        nav=nav,
        notes=ARTIFACT_NOTES,
        mark_json=json.dumps(mark),
        leaflet_js=read("vendor/leaflet.js"),
        markercluster_js=read("vendor/markercluster.js"),
        data_json=json.dumps(payload, separators=(",", ":")),
        tiles_json=json.dumps({"satellite": satellite, "streets": streets}, separators=(",", ":")),
        max_native=MAX_NATIVE_ZOOM,
        max_zoom=MAX_ZOOM,
        site_js=js,
    )


PAGE = r"""<title>Loudoun Data Center Watch</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>{font_css}</style>
<style>{leaflet_css}</style>
<style>{markercluster_css}</style>
<style>{css}</style>
<style>
/* ---- Artifact-only shell ------------------------------------------------
   The deployed site is thirteen HTML pages sharing one stylesheet. An artifact
   is one page, so the sections live in the same document and a tab switches
   between them. Everything below is scoped to .artifact-* so it cannot collide
   with the site's own classes. */
.artifact-tabs {{
  display: flex;
  flex-wrap: wrap;
  gap: var(--space-1);
}}
.artifact-tab {{
  appearance: none;
  border: 0;
  background: none;
  cursor: pointer;
  font: inherit;
  font-family: var(--font-sans);
  font-size: var(--text-sm);
  font-weight: var(--weight-semibold);
  color: var(--text-muted);
  padding: var(--space-2) var(--space-3);
  border-bottom: var(--rule-heavy) solid transparent;
}}
.artifact-tab:hover {{ color: var(--text); }}
.artifact-tab.is-current {{ color: var(--text); border-bottom-color: var(--text); }}
.artifact-tab:focus-visible {{ outline: 2px solid var(--focus-ring); outline-offset: -2px; }}
.artifact-section[hidden] {{ display: none !important; }}
/* .banner is a flex ROW in the site's stylesheet — it was written for a single
   line of text plus an icon. This note has three stacked blocks, which in a row
   refuse to shrink and push the page sideways. */
.demo-note {{ display: block; }}
.demo-note p {{ margin: 0 0 var(--space-2); }}
.demo-note p:last-child {{ margin-bottom: 0; }}
.demo-note ul {{ margin: 0 0 var(--space-2); padding-left: var(--space-4); }}
.demo-note li {{ margin-bottom: var(--space-1); }}
body {{ background: var(--bg); color: var(--text); }}
</style>

<header class="site-header" id="site-header">
  <div class="container site-header__inner">
    <a class="brand" href="#" data-section-link="map">
      <span class="brand__mark" data-county-mark aria-hidden="true"></span>
      <span class="brand__name">Loudoun Data Center Watch</span>
      <span class="brand__name--short">LDC Watch</span>
    </a>
    <nav class="site-nav" aria-label="Sections">
      <div class="artifact-tabs">{nav}</div>
    </nav>
  </div>
</header>

<div id="watch-ticker" hidden></div>

<main id="main">
  <!-- MAP -->
  <section class="artifact-section" data-section="map">
    <div class="hero">
      <div class="hero__grain" aria-hidden="true"></div>
      <div class="container container-wide">
        <div class="hero__grid">
          <div class="hero__copy">
            <p class="hero__eyebrow"><span class="hero__pulse" aria-hidden="true"></span>Loudoun County, Virginia</p>
            <h1 class="hero__title">The data centers are mapped.<br>The people living beside them are&nbsp;not.</h1>
            <p class="hero__lead">Loudoun holds the largest concentration of data centers on earth.
            Below is every one of them, from the county's own records &mdash; and what residents
            say about living next to them.</p>
            <dl class="hero__figures">
              <div><dt>Parcels</dt><dd>224</dd></div>
              <div><dt>Operational</dt><dd>103</dd></div>
              <div><dt>Proposed</dt><dd>85</dd></div>
              <div><dt>Floor area</dt><dd>114.4M ft&sup2;</dd></div>
            </dl>
          </div>
          <figure class="hero-fig">
            <div id="hero-figure" class="hero-fig__stage"></div>
            <figcaption class="hero-fig__caption" id="hero-figure-caption"></figcaption>
          </figure>
        </div>
      </div>
    </div>

    <div class="container">
      <div class="page-header" style="margin-top: var(--space-6)">
        <p class="kicker">The map</p>
        <h2>Every parcel, and every report</h2>
        <p class="lead">Switch to satellite and turn on parcel boundaries to see the real
        footprints against the neighbourhoods.</p>
      </div>
      <div class="stat-grid stat-grid--4" id="headline-stats"></div>
      {notes}
      <div class="map-shell" style="margin-top: var(--space-5)">
        <div id="layer-toggles"></div>
        <div id="map-controls"></div>
        <div class="map" id="map"></div>
      </div>
    </div>
  </section>

  <!-- REPORTS -->
  <section class="artifact-section" data-section="reports" hidden>
    <div class="container">
      <div class="page-header">
        <p class="kicker">From residents</p>
        <h1>Community reports</h1>
        <p class="lead">What residents say about living beside these facilities. Click any report
        to open the full record.</p>
      </div>
      <div id="report-results"></div>
    </div>
  </section>

  <!-- WATCHLIST -->
  <section class="artifact-section" data-section="watchlist" hidden>
    <div class="container"><div id="watchlist-body"></div></div>
  </section>

  <!-- NEWS -->
  <section class="artifact-section" data-section="news" hidden>
    <div class="container">
      <div class="page-header">
        <p class="kicker">Coverage</p>
        <h1>In the news</h1>
        <p class="lead">Real headlines, collected from public news feeds.</p>
      </div>
      <div class="chips" id="news-filters"></div>
      <div class="row row-between" style="margin-bottom: var(--space-4)">
        <p class="filter-bar__result" id="news-count" role="status" aria-live="polite" style="margin:0">&mdash;</p>
        <p class="tiny muted" id="news-generated" style="margin:0"></p>
      </div>
      <div id="news-list"></div>
      <p style="text-align:center;margin-top:var(--space-5)">
        <button class="btn btn--secondary" type="button" id="news-more" hidden></button>
      </p>
    </div>
  </section>

  <!-- STATS -->
  <section class="artifact-section" data-section="stats" hidden>
    <div class="container">
      <div class="page-header">
        <p class="kicker">The scale of it</p>
        <h1>Statistics</h1>
      </div>
      <div id="artifact-stats"></div>
    </div>
  </section>

  <!-- ABOUT -->
  <section class="artifact-section" data-section="about" hidden>
    <div class="container">
      <div class="page-header">
        <p class="kicker">What this is</p>
        <h1>About</h1>
      </div>
      <div class="prose">
        <p>Loudoun County holds the largest concentration of data centers on earth. This is an
        independent record of how that is affecting the people who live next to it &mdash; the
        county's own facility data on one map, and residents' first-hand accounts on the same map
        beside it.</p>

        <h2>Where the facility data comes from</h2>
        <p>Every parcel, boundary and building outline is pulled directly from Loudoun County
        GIS &mdash; nothing here is estimated or invented. The snapshot is 224 parcels: 103
        operational, 36 under construction and 85 in the approval pipeline, across 271 building
        footprints and about 114.4 million square feet.</p>
        <p>Ownership fields are the recorded property owner in county land records. That is very
        often a holding company rather than the business operating the building, it can be out of
        date, and it says nothing about who is responsible for any condition a resident reports.</p>

        <h2>How reports are handled</h2>
        <p>A reporter's name, email, phone and street address are <strong>never published</strong>
        &mdash; not on the site, not in any export, not in the page source. Map pins are offset
        100&ndash;200 metres from the address given, generated once when the report is stored, so
        a report can be placed in a neighbourhood without identifying a household. Photos are
        re-encoded in the browser to strip GPS data before they are ever uploaded. Nothing appears
        publicly until a person has reviewed it.</p>

        <h2>What a report is, and is not</h2>
        <p>Reports are unverified first-hand accounts. They are moderated, but they are not
        investigated, measured or corroborated. A report is not a finding of fact, and it does not
        establish that any company caused any condition described.</p>

        <div class="callout callout--muted">
          <p><strong>Not affiliated with anyone.</strong> This project has no connection to
          Loudoun County government, to Erin Brockovich or the Brockovich data center reporting
          project, or to any data center owner, operator or tenant.</p>
        </div>
      </div>
    </div>
  </section>
</main>

<footer class="site-footer" id="site-footer"></footer>

<script>{leaflet_js}</script>
<script>{markercluster_js}</script>
<script>
/* Everything the site would normally fetch, inlined. */
window.__LDCW_DATA = {data_json};
window.__LDCW_TILES = {tiles_json};
window.__LDCW_MARK = {mark_json};
</script>
<script>{site_js}</script>
<script>
(function () {{
  "use strict";
  var LDCW = window.LDCW;

  /* ---- Serve data from memory instead of the network --------------------
     Override fetch itself rather than the store's helpers. store.js,
     map-layers.js and layout.js each hold their own closure over fetch, so
     replacing Store.loadJson only catches one of the three and the parcel
     overlay silently stays empty. Patching the one function they all bottom
     out in catches every caller, including any added later. */
  var realFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {{
    var url = typeof input === "string" ? input : (input && input.url) || "";
    var key = String(url).replace(/^\.\//, "").split("?")[0];

    if (key.indexOf("loudoun-mark.svg") !== -1) {{
      return Promise.resolve(new Response(window.__LDCW_MARK, {{
        status: 200, headers: {{ "Content-Type": "image/svg+xml" }}
      }}));
    }}
    var hit = window.__LDCW_DATA[key];
    if (hit) {{
      return Promise.resolve(new Response(JSON.stringify(hit), {{
        status: 200, headers: {{ "Content-Type": "application/json" }}
      }}));
    }}
    // Anything not bundled would be a blocked cross-origin request in the real
    // artifact. Fail it here the same way, rather than letting it hang.
    if (/^https?:|^file:/.test(key)) {{
      return Promise.reject(new TypeError("blocked in artifact: " + key));
    }}
    return realFetch(input, init);
  }};

  /* ---- Tiles from memory ------------------------------------------------
     A TileLayer that resolves {{z}}/{{y}}/{{x}} against the bundled cache. Tiles
     outside the cached area resolve to a transparent pixel rather than a
     broken-image icon, so the edge of the cache looks like empty ground
     rather than a fault. */
  var BLANK = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7";
  var CachedTiles = L.TileLayer.extend({{
    initialize: function (key, options) {{
      this._cacheKey = key;
      L.TileLayer.prototype.initialize.call(this, "", options);
    }},
    getTileUrl: function (coords) {{
      var cache = window.__LDCW_TILES[this._cacheKey] || {{}};
      var z = Math.min(coords.z, {max_native});
      var scale = Math.pow(2, coords.z - z);
      var x = Math.floor(coords.x / scale);
      var y = Math.floor(coords.y / scale);
      return cache[z + "/" + y + "/" + x] || BLANK;
    }}
  }});

  var settings = window.LDCW_CONFIG;
  settings.BASEMAPS = settings.BASEMAPS.filter(function (def) {{
    return def.key === "streets" || def.key === "satellite";
  }});
  settings.BASEMAPS.forEach(function (def) {{
    def.maxZoom = {max_zoom};
    def.hint = def.hint + " (built-in cache, zoom 10-12)";
  }});

  var buildBasemaps = LDCW.mapLayers.buildBasemaps;
  LDCW.mapLayers.buildBasemaps = function (map) {{
    var defs = settings.BASEMAPS;
    var layers = {{}};
    var active = null;
    defs.forEach(function (def) {{
      layers[def.key] = new CachedTiles(def.key, {{
        attribution: def.attribution,
        maxNativeZoom: {max_native},
        maxZoom: {max_zoom}
      }});
    }});
    function select(key) {{
      var def = defs.filter(function (d) {{ return d.key === key; }})[0];
      if (!def) return null;
      if (active && layers[active]) map.removeLayer(layers[active]);
      layers[key].addTo(map);
      layers[key].bringToBack();
      active = key;
      map.getContainer().classList.toggle("map--dark-base", def.dark === true);
      return def;
    }}
    return {{ defs: defs, select: select, active: function () {{ return active; }} }};
  }};

  /* ---- Turn off what genuinely cannot work here -------------------------
     Address search calls Nominatim, which the CSP blocks. Leaving the control
     visible so it can fail is worse than not offering it. Geolocation is a
     browser API rather than a request, so that one stays. */
  var search = document.querySelector(".map-search");
  if (search) {{
    search.hidden = true;
    var results = document.querySelector(".map-search__results");
    if (results) results.hidden = true;
    var note = document.createElement("p");
    note.className = "tiny muted";
    note.style.margin = "0";
    note.textContent = "Address search needs a lookup service, which this in-app version cannot reach.";
    search.parentNode.insertBefore(note, search);
  }}

  /* ---- Section switching ------------------------------------------------ */
  var sections = Array.prototype.slice.call(document.querySelectorAll(".artifact-section"));
  var tabs = Array.prototype.slice.call(document.querySelectorAll(".artifact-tab"));

  function show(key) {{
    sections.forEach(function (node) {{
      node.hidden = node.getAttribute("data-section") !== key;
    }});
    tabs.forEach(function (tab) {{
      tab.classList.toggle("is-current", tab.getAttribute("data-section") === key);
    }});
    // Leaflet measures its container on creation. A map that was hidden at
    // that moment renders one grey tile until it is told to re-measure.
    if (key === "map" && LDCW.map.current) {{
      setTimeout(function () {{ LDCW.map.current.invalidate(); }}, 30);
    }}
    window.scrollTo({{ top: 0, behavior: "auto" }});
  }}

  tabs.forEach(function (tab) {{
    tab.addEventListener("click", function () {{ show(tab.getAttribute("data-section")); }});
  }});
  document.querySelectorAll("[data-section-link]").forEach(function (link) {{
    link.addEventListener("click", function (event) {{
      event.preventDefault();
      show(link.getAttribute("data-section-link"));
    }});
  }});

  /* ---- The county mark, normally fetched as an SVG file ------------------ */
  document.querySelectorAll("[data-county-mark]").forEach(function (slot) {{
    slot.innerHTML = window.__LDCW_MARK;
  }});

  /* ---- Footer ----------------------------------------------------------- */
  document.getElementById("site-footer").innerHTML =
    '<div class="container"><div class="site-footer__disclaimer">' +
    '<p><strong>This is an independent community project.</strong> It is not affiliated with, ' +
    'endorsed by, or operated by Loudoun County government, Erin Brockovich, or any data center ' +
    'owner or operator. Community reports shown here are illustrative samples, not real ' +
    'submissions, and are not findings of fact.</p>' +
    '<p>Facility data &copy; Loudoun County GIS. Satellite imagery &copy; Esri, Maxar, Earthstar ' +
    'Geographics. Street tiles &copy; OpenStreetMap contributors.</p>' +
    '</div></div>';

  /* ---- Boot ------------------------------------------------------------- */
  var Store = LDCW.Store;
  var schema = LDCW.schema;

  var mapController = LDCW.map.createMap("map", {{
    ariaLabel: "Map of Loudoun County data centers and community reports."
  }});
  LDCW.map.renderLayerToggles(document.getElementById("layer-toggles"));
  LDCW.map.renderMapControls(document.getElementById("map-controls"), mapController);
  mapController.bindToggles(document.getElementById("layer-toggles"));

  Store.loadFacilities().then(function (facilities) {{
    mapController.setFacilities(facilities);
  }});
  Store.listApproved({{}}).then(function (reports) {{
    mapController.setReports(reports);
    LDCW.ui.renderReportList(document.getElementById("report-results"), reports);
  }});

  Store.loadSummary().then(function (summary) {{
    // summary.json nests the breakdown under `counts`, not `by_status`.
    var counts = summary.counts || {{}};
    var tiles = [
      [schema.formatNumber(summary.total), "Data center parcels"],
      [schema.formatNumber(counts.operational), "Operational"],
      [schema.formatNumber(counts.under_construction), "Under construction"],
      [schema.formatNumber(counts.proposed), "Proposed"]
    ];
    document.getElementById("headline-stats").innerHTML = tiles.map(function (t) {{
      return '<div class="stat"><span class="stat__value">' + t[0] +
             '</span><span class="stat__label">' + t[1] + "</span></div>";
    }}).join("");
  }});

  /* Statistics section — the deployed site has a fuller dashboard; this is
     the same numbers, laid out simply. */
  Promise.all([Store.stats({{}}), Store.loadFacilities()]).then(function (results) {{
    var stats = results[0];
    var districtCounts = {{}};
    results[1].forEach(function (f) {{
      if (f.district) districtCounts[f.district] = (districtCounts[f.district] || 0) + 1;
    }});
    var districtRows = Object.keys(districtCounts).map(function (k) {{
      return {{ label: k, count: districtCounts[k] }};
    }}).sort(function (a, b) {{ return b.count - a.count; }});
    var host = document.getElementById("artifact-stats");
    function bars(rows, total) {{
      return '<table class="chart"><tbody>' + rows.map(function (row) {{
        var pct = total ? Math.round((row.count / total) * 100) : 0;
        return '<tr><th class="chart__label">' + schema.escapeHtml(row.label) + "</th>" +
          '<td class="chart__bar-cell"><span class="chart__track">' +
          (row.count ? '<span class="chart__bar" style="width:' + pct + '%"></span>' : "") +
          "</span></td>" +
          '<td class="chart__value">' + schema.formatNumber(row.count) + "</td></tr>";
      }}).join("") + "</tbody></table>";
    }}
    host.innerHTML =
      "<h2>Data center parcels by district</h2>" +
      bars(districtRows, 224) +
      "<h2 style=\"margin-top:var(--space-6)\">What residents report</h2>" +
      bars((stats.byCategory || []).map(function (row) {{
        return {{ label: schema.categoryLabel(row.key), count: row.count }};
      }}), stats.total || 1);
  }}).catch(function () {{}});

  LDCW.watchlist.mountTicker();
  LDCW.watchlist.mountPage();
  LDCW.news.mountPage();

  show("map");
}})();
</script>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    parser.add_argument("-o", "--output", default=os.path.join(ROOT, "artifact.html"))
    parser.add_argument("--tiles-satellite", default="")
    parser.add_argument("--tiles-streets", default="")
    parser.add_argument("--news-limit", type=int, default=120)
    args = parser.parse_args()

    html = build(args.tiles_satellite, args.tiles_streets, args.news_limit)

    with open(args.output, "w", encoding="utf-8") as handle:
        handle.write(html)

    size = os.path.getsize(args.output)
    print(f"Wrote {args.output}  {size / 1024 / 1024:.2f} MB")
    if size > 16 * 1024 * 1024:
        print("  WARNING: over the 16 MB artifact limit", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
