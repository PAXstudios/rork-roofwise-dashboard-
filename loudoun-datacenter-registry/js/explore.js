/*
 * The full-screen map.
 *
 * Same data as the home page, a different premise: here the map is the whole
 * page and everything else floats over it. That changes four things.
 *
 *   1. The view is addressable. Latitude, longitude, zoom, basemap, which
 *      marker layers are on, which overlays are on and the active filter all
 *      live in the query string, so "look at this" is a link. Everything is
 *      restored on load, and rewritten (replaceState, not pushState — panning
 *      a map should not fill the back button with history) as the reader moves.
 *
 *   2. The panel lists what is IN VIEW, nearest the middle of the screen
 *      first, and re-sorts as you pan. On a page-sized map the useful question
 *      is "what exists"; on a full-screen map it is "what am I looking at".
 *      It is also this page's accessible copy of the map, which is why the
 *      skip link points at it and why every row is a real button.
 *
 *   3. Tapping a marker opens the panel, not a popup. A Leaflet bubble covers
 *      a third of a phone screen and puts its own close button under your
 *      thumb; the sheet is already there and already scrolls.
 *
 *   4. The sheet is draggable, with three snap points. It is NOT a modal: the
 *      map stays live behind it, and dragging it down leaves a peek strip
 *      showing the counts rather than dismissing it entirely, so the reader
 *      never loses the way back to the list.
 *
 * Nothing here is required for the data to be reachable. With JavaScript off,
 * the <noscript> block sends the reader to the list pages, which carry the
 * same records as ordinary HTML.
 */

(function (LDCW) {
  "use strict";

  var schema = LDCW.schema;
  var Store = LDCW.Store;
  var escape = schema.escapeHtml;

  var M_PER_MILE = 1609.344;

  /* Snap points. `half` and `full` are fractions of the viewport; `peek` is
     measured, because it has to be exactly tall enough for the grip and the
     count line and that depends on which fonts have finished loading. Guessing
     a number here leaves a row of the list sliced in half, which reads as a
     rendering bug rather than an invitation to pull. */
  var PEEK_FALLBACK = 96;
  var SNAPS = ["peek", "half", "full"];

  /* How many rows the panel builds per pan. See renderList — the total in view
     is still counted and stated, this only bounds the DOM. */
  var ROW_LIMIT = 200;

  var state = {
    controller: null,
    facilities: [],
    reports: [],
    snap: "peek",
    mode: "list", // "list" | "detail"
    selected: null,
    drawer: null, // "layers" | "menu" | null
  };

  var els = {};

  function reduced() {
    return LDCW.motion ? LDCW.motion.prefersReducedMotion() : false;
  }

  function isDesktop() {
    return window.matchMedia("(min-width: 900px)").matches;
  }

  /* ---- URL state ----------------------------------------------------------
     One place that knows the parameter names, so the reader and the writer
     cannot disagree about them. */

  var PARAM = {
    lat: "lat",
    lng: "lng",
    zoom: "zoom",
    base: "base",
    layers: "layers",
    overlays: "overlays",
    district: "district",
    category: "category",
    q: "q",
  };

  var ALL_LAYERS = ["operational", "under_construction", "proposed", "reports"];

  function readUrl() {
    var params = new URLSearchParams(window.location.search);
    var out = {};

    var lat = parseFloat(params.get(PARAM.lat));
    var lng = parseFloat(params.get(PARAM.lng));
    var zoom = parseFloat(params.get(PARAM.zoom));
    if (isFinite(lat) && isFinite(lng)) out.centre = [lat, lng];
    if (isFinite(zoom)) out.zoom = zoom;

    if (params.get(PARAM.base)) out.base = params.get(PARAM.base);

    // An absent `layers` means "all of them". An EMPTY layers means the reader
    // deliberately turned everything off, which is a different thing, so the
    // two cases must not collapse into one.
    if (params.has(PARAM.layers)) {
      out.layers = params
        .get(PARAM.layers)
        .split(",")
        .filter(function (key) {
          return ALL_LAYERS.indexOf(key) !== -1;
        });
    }

    if (params.get(PARAM.overlays)) {
      out.overlays = params.get(PARAM.overlays).split(",").filter(Boolean);
    }

    out.filter = {};
    if (params.get(PARAM.district)) out.filter.locality = params.get(PARAM.district);
    if (params.get(PARAM.category)) out.filter.categories = [params.get(PARAM.category)];
    if (params.get(PARAM.q)) out.filter.search = params.get(PARAM.q);

    return out;
  }

  function currentUrl() {
    var map = state.controller && state.controller.map;
    var params = new URLSearchParams();

    if (map) {
      var centre = map.getCenter();
      params.set(PARAM.lat, centre.lat.toFixed(5));
      params.set(PARAM.lng, centre.lng.toFixed(5));
      params.set(PARAM.zoom, String(Math.round(map.getZoom() * 100) / 100));
    }

    var basemaps = state.controller && state.controller.basemaps;
    if (basemaps && basemaps.active()) params.set(PARAM.base, basemaps.active());

    var on = ALL_LAYERS.filter(function (key) {
      return state.controller.layerVisible(key);
    });
    // Only spend a parameter when it says something. All four on is the
    // default, and a link is easier to read without it.
    if (on.length !== ALL_LAYERS.length) params.set(PARAM.layers, on.join(","));

    var overlaysOn = (LDCW.mapLayers ? LDCW.mapLayers.OVERLAY_DEFS : [])
      .map(function (def) {
        return def.key;
      })
      .filter(function (key) {
        return state.controller.overlayEnabled(key);
      });
    if (overlaysOn.length) params.set(PARAM.overlays, overlaysOn.join(","));

    var filter = state.filter || {};
    if (filter.locality) params.set(PARAM.district, filter.locality);
    if (filter.categories && filter.categories.length) {
      params.set(PARAM.category, filter.categories[0]);
    }
    if (filter.search) params.set(PARAM.q, filter.search);

    return window.location.pathname + "?" + params.toString();
  }

  var writePending = null;

  function writeUrl() {
    // Panning fires continuously. Rewriting the URL on every frame is wasted
    // work and, in some browsers, a rate-limit warning in the console.
    if (writePending) clearTimeout(writePending);
    writePending = setTimeout(function () {
      writePending = null;
      if (!state.controller) return;
      window.history.replaceState(null, "", currentUrl());
    }, 220);
  }

  /* ---- Status line -------------------------------------------------------- */

  var statusTimer = null;

  function say(message, isError) {
    if (!els.status) return;
    if (statusTimer) clearTimeout(statusTimer);

    if (!message) {
      els.status.hidden = true;
      els.status.textContent = "";
      return;
    }

    els.status.textContent = message;
    els.status.classList.toggle("is-error", isError === true);
    els.status.hidden = false;

    // Errors stay until replaced; confirmations clear themselves, because a
    // stale "copied" floating over the map reads as a bug.
    if (!isError) {
      statusTimer = setTimeout(function () {
        els.status.hidden = true;
      }, 4200);
    }
  }

  /* ---- Chips -------------------------------------------------------------- */

  function renderChips() {
    els.chips.innerHTML = LDCW.map.LAYER_DEFS.map(function (def) {
      return (
        '<button type="button" class="chip chip--' +
        def.key +
        '" data-layer="' +
        def.key +
        '" aria-pressed="true">' +
        '<span class="chip__dot" aria-hidden="true"></span>' +
        "<span>" +
        escape(def.label) +
        "</span>" +
        // map.js writes counts into every [data-layer-count] on the page, so
        // the chips stay in step with the map for free.
        '<span class="chip__count" data-layer-count="' +
        def.key +
        '">—</span></button>'
      );
    }).join("");

    els.chips.querySelectorAll("[data-layer]").forEach(function (button) {
      button.addEventListener("click", function () {
        var key = button.getAttribute("data-layer");
        var next = button.getAttribute("aria-pressed") !== "true";
        button.setAttribute("aria-pressed", String(next));
        state.controller.setLayerVisible(key, next);
        renderList();
        writeUrl();
      });
    });
  }

  function setChip(key, on) {
    var button = els.chips.querySelector('[data-layer="' + key + '"]');
    if (button) button.setAttribute("aria-pressed", String(on));
  }

  /* ---- The sheet ----------------------------------------------------------
     Height is a CSS custom property so the floating rail can sit above it with
     a plain calc() instead of a resize observer. */

  function peekHeight() {
    var head = els.sheet.querySelector(".explore__sheet-head");
    if (!head || !els.grip.offsetHeight) return PEEK_FALLBACK;
    // offsetHeight rounds down, so summing two of them can land a fraction of
    // a pixel short and clip the head's bottom rule. Two pixels of slack turns
    // that into a clean divider.
    return els.grip.offsetHeight + head.offsetHeight + 2;
  }

  function snapHeight(snap) {
    var vh = window.innerHeight;
    if (snap === "full") return Math.round(vh * 0.88);
    if (snap === "half") return Math.round(vh * 0.5);
    return peekHeight();
  }

  function setSnap(snap, opts) {
    state.snap = snap;
    // --peek-h anchors the rail, the scale bar and the attribution. It is
    // written here as well as on resize because the first pass runs before the
    // web fonts land, which changes how tall the count line is.
    els.root.style.setProperty("--peek-h", peekHeight() + "px");
    els.root.style.setProperty("--sheet-h", snapHeight(snap) + "px");
    els.grip.setAttribute("aria-expanded", String(snap !== "peek"));
    els.sheet.classList.toggle("is-open", snap !== "peek");
    if (opts && opts.focus && snap !== "peek") els.list.focus({ preventScroll: true });
  }

  function bindSheetDrag() {
    var startY = 0;
    var startH = 0;
    var dragging = false;
    var moved = false;

    function down(event) {
      // The sheet is a side panel on a desktop; there is nothing to drag.
      if (isDesktop()) return;
      dragging = true;
      moved = false;
      startY = event.clientY;
      startH = els.sheet.getBoundingClientRect().height;
      els.sheet.classList.add("is-dragging");
      els.grip.setPointerCapture(event.pointerId);
    }

    function move(event) {
      if (!dragging) return;
      var delta = startY - event.clientY;
      if (Math.abs(delta) > 4) moved = true;
      var height = Math.min(
        snapHeight("full"),
        Math.max(peekHeight(), startH + delta)
      );
      els.root.style.setProperty("--sheet-h", height + "px");
    }

    function up(event) {
      if (!dragging) return;
      dragging = false;
      els.sheet.classList.remove("is-dragging");
      if (els.grip.hasPointerCapture(event.pointerId)) {
        els.grip.releasePointerCapture(event.pointerId);
      }

      // A tap, not a drag: cycle to the next snap point. That makes the grip
      // work for a reader who taps rather than drags, and for a keyboard,
      // which cannot drag at all.
      if (!moved) {
        var index = SNAPS.indexOf(state.snap);
        setSnap(SNAPS[(index + 1) % SNAPS.length], { focus: true });
        return;
      }

      // Otherwise settle on whichever snap point is nearest where they let go.
      var height = els.sheet.getBoundingClientRect().height;
      var nearest = SNAPS[0];
      var best = Infinity;
      SNAPS.forEach(function (snap) {
        var distance = Math.abs(snapHeight(snap) - height);
        if (distance < best) {
          best = distance;
          nearest = snap;
        }
      });
      setSnap(nearest);
    }

    els.grip.addEventListener("pointerdown", down);
    els.grip.addEventListener("pointermove", move);
    els.grip.addEventListener("pointerup", up);
    els.grip.addEventListener("pointercancel", up);

    // Keyboard: the grip is a real button, so Enter and Space already cycle
    // through the click path above. Arrow keys give finer control.
    els.grip.addEventListener("keydown", function (event) {
      var index = SNAPS.indexOf(state.snap);
      if (event.key === "ArrowUp" && index < SNAPS.length - 1) {
        event.preventDefault();
        setSnap(SNAPS[index + 1]);
      } else if (event.key === "ArrowDown" && index > 0) {
        event.preventDefault();
        setSnap(SNAPS[index - 1]);
      }
    });
  }

  /* ---- The list ----------------------------------------------------------- */

  function distanceLabel(metres) {
    var miles = metres / M_PER_MILE;
    if (miles < 0.1) return (metres < 1000 ? Math.round(metres) + " m" : miles.toFixed(1) + " mi");
    return miles.toFixed(miles < 10 ? 1 : 0) + " mi";
  }

  function resultRow(entry) {
    var record = entry.record;

    if (entry.kind === "facility") {
      var bits = [schema.statusLabel(record.status)];
      if (record.district) bits.push(record.district);
      var sqft = schema.formatSqft(record.sqft);
      if (sqft) bits.push(sqft);

      return (
        '<button type="button" class="result" data-kind="facility" data-id="' +
        escape(record.id) +
        '">' +
        '<span class="result__dot result__dot--' +
        escape(record.status) +
        '" aria-hidden="true"></span>' +
        '<span class="result__main"><span class="result__name">' +
        escape(record.name || "Data center parcel") +
        '</span><span class="result__meta">' +
        escape(bits.join(" · ")) +
        "</span></span>" +
        '<span class="result__dist">' +
        escape(distanceLabel(entry.distance)) +
        "</span></button>"
      );
    }

    var categories = (record.categories || [])
      .slice(0, 3)
      .map(function (key) {
        return schema.categoryLabel(key);
      })
      .join(", ");

    return (
      '<button type="button" class="result" data-kind="report" data-id="' +
      escape(record.id) +
      '">' +
      '<span class="result__dot result__dot--report" aria-hidden="true"></span>' +
      '<span class="result__main"><span class="result__name">' +
      escape(categories || "Community report") +
      '</span><span class="result__meta">' +
      escape(
        (record.locality || "Loudoun County") +
          " · impact " +
          record.severity +
          "/5 · " +
          schema.formatRelative(record.created_at)
      ) +
      "</span></span>" +
      '<span class="result__dist">' +
      escape(distanceLabel(entry.distance)) +
      "</span></button>"
    );
  }

  function renderList() {
    if (state.mode === "detail") return;
    if (!state.controller) return;

    // Count everything in view, but only build rows for the nearest 200:
    // rendering all 224 parcels plus every report on each pan is the one thing
    // that makes this page feel heavy on a phone. The cap is stated below
    // rather than left silent — a truncated list that claims to be complete is
    // worse than a slow one.
    var entries = state.controller.inBounds();
    var counts = state.controller.getCounts();

    var facilities = entries.filter(function (entry) {
      return entry.kind === "facility";
    }).length;
    var reports = entries.length - facilities;
    var shown = entries.slice(0, ROW_LIMIT);

    var countyFacilities =
      counts.operational + counts.under_construction + counts.proposed;

    els.sheetTitle.textContent = "In this view";
    // "184 facilities · 224 in the county" reads as two unrelated numbers.
    // "184 of 224" says the thing the reader actually wants to know, which is
    // how much of the county they can currently see.
    els.sheetSub.textContent =
      facilities +
      " of " +
      countyFacilities +
      (countyFacilities === 1 ? " facility" : " facilities") +
      "  ·  " +
      reports +
      " of " +
      counts.reports +
      (counts.reports === 1 ? " report" : " reports");
    els.sheetClose.hidden = true;

    if (!entries.length) {
      els.list.innerHTML =
        '<p class="explore__empty">Nothing in view.<br />Zoom out, pan toward Ashburn and Sterling, ' +
        "or turn a layer back on above.</p>";
      return;
    }

    els.list.innerHTML =
      shown.map(resultRow).join("") +
      (entries.length > shown.length
        ? '<p class="explore__empty">Showing the nearest ' +
          shown.length +
          " of " +
          entries.length +
          " in view. Zoom in to narrow it down.</p>"
        : "");

    els.list.querySelectorAll(".result").forEach(function (button) {
      button.addEventListener("click", function () {
        select(button.getAttribute("data-kind"), button.getAttribute("data-id"), {
          fly: true,
        });
      });
    });
  }

  /* ---- Detail ------------------------------------------------------------- */

  function findRecord(kind, id) {
    var list = kind === "facility" ? state.facilities : state.reports;
    for (var i = 0; i < list.length; i += 1) {
      if (String(list[i].id) === String(id)) return list[i];
    }
    return null;
  }

  function facilityDetail(facility) {
    var rows = [];
    if (facility.operator) rows.push(["Property owner", facility.operator]);
    if (facility.district) rows.push(["District", facility.district]);
    var sqft = schema.formatSqft(facility.sqft);
    if (sqft) rows.push(["Floor area", sqft]);
    if (facility.acres) rows.push(["Parcel", facility.acres + " acres"]);
    if (facility.zoning) rows.push(["Zoning", facility.zoning]);
    if (facility.zoning_case) rows.push(["Case", facility.zoning_case]);
    if (facility.application) rows.push(["Application", facility.application]);
    if (facility.status_raw) rows.push(["County status", facility.status_raw]);

    var near = state.controller.countWithin(facility.lat, facility.lng, M_PER_MILE);

    return (
      '<div class="explore__detail">' +
      "<h3>" +
      escape(facility.name || "Data center parcel") +
      "</h3>" +
      '<span class="badge badge--' +
      escape(facility.status) +
      '">' +
      escape(schema.statusLabel(facility.status)) +
      "</span>" +
      (rows.length
        ? "<dl>" +
          rows
            .map(function (pair) {
              return "<dt>" + escape(pair[0]) + "</dt><dd>" + escape(pair[1]) + "</dd>";
            })
            .join("") +
          "</dl>"
        : "") +
      "<p><strong>Within one mile:</strong> " +
      near.facilities +
      (near.facilities === 1 ? " facility" : " facilities") +
      " and " +
      near.reports +
      (near.reports === 1 ? " community report" : " community reports") +
      ".</p>" +
      '<p>Source: Loudoun County GIS. The owner shown is the recorded property owner, ' +
      "which is often a holding company rather than the operator.</p>" +
      '<div class="explore__detail-actions">' +
      '<a class="btn btn--primary btn--sm" href="report.html">Report an issue near here</a>' +
      '<button type="button" class="btn btn--ghost btn--sm" data-act="ring">Count within 1, 2 and 5 miles</button>' +
      "</div></div>"
    );
  }

  function reportDetail(report) {
    var badges = (report.categories || [])
      .map(function (key) {
        return '<span class="badge badge--neutral">' + escape(schema.categoryLabel(key)) + "</span>";
      })
      .join("");

    return (
      '<div class="explore__detail">' +
      "<h3>" +
      escape(report.locality || "Loudoun County") +
      (report.zip ? " " + escape(report.zip) : "") +
      "</h3>" +
      '<div class="badge-list">' +
      badges +
      "</div>" +
      "<p>" +
      escape(report.description || "") +
      "</p>" +
      "<p>Reported " +
      escape(schema.formatRelative(report.created_at)) +
      " · impact " +
      escape(String(report.severity)) +
      "/5 · the pin is offset from the address given, on purpose.</p>" +
      (report.is_demo
        ? "<p><strong>Sample report.</strong> Illustrative only — not a real submission.</p>"
        : "") +
      '<div class="explore__detail-actions">' +
      '<a class="btn btn--secondary btn--sm" href="report-detail.html?id=' +
      encodeURIComponent(report.id) +
      '">Open the full report</a>' +
      "</div></div>"
    );
  }

  function select(kind, id, opts) {
    var record = findRecord(kind, id);
    if (!record) return;

    opts = opts || {};
    state.mode = "detail";
    state.selected = { kind: kind, id: id };

    els.sheetTitle.textContent = kind === "facility" ? "Facility" : "Community report";
    els.sheetSub.textContent = kind === "facility" ? "Loudoun County records" : "Resident account";
    els.sheetClose.hidden = false;
    els.list.innerHTML =
      '<button type="button" class="explore__back">&larr; Back to what is in view</button>' +
      (kind === "facility" ? facilityDetail(record) : reportDetail(record));

    els.list.querySelector(".explore__back").addEventListener("click", backToList);

    var ring = els.list.querySelector('[data-act="ring"]');
    if (ring) {
      ring.addEventListener("click", function () {
        showRings(record);
      });
    }

    // The sheet must be big enough to read but must not swallow the map — the
    // reader still needs to see where the thing they tapped actually is.
    if (!isDesktop() && state.snap === "peek") setSnap("half");
    els.list.scrollTop = 0;

    if (opts.fly) {
      state.controller.focus(record.lat, record.lng, Math.max(state.controller.map.getZoom(), 14));
    }
  }

  function backToList() {
    state.mode = "list";
    state.selected = null;
    renderList();
    els.list.scrollTop = 0;
  }

  function showRings(record) {
    if (!state.rings) return;
    state.rings.at(L.latLng(record.lat, record.lng));
  }

  /* ---- Drawer -------------------------------------------------------------
     One element, two contents. Keeping them in one drawer means one focus
     trap, one Escape handler and one scrim rather than two of each. */

  /* Zoom 11, x 583, y 782 — the tile covering the Ashburn/Sterling corridor.
     The swatch shows each service rendering the ground the reader is actually
     looking at rather than a coloured rectangle standing in for it.

     The placeholders are substituted by NAME, which matters: OpenStreetMap and
     CARTO address tiles {z}/{x}/{y} while the Esri and USGS services use
     {z}/{y}/{x}. Interpolating positionally would silently fetch a tile of
     somewhere else entirely. All seven were fetched and return real imagery at
     these coordinates. */
  function swatchStyle(def) {
    var url = def.url
      .replace("{z}", "11")
      .replace("{x}", "583")
      .replace("{y}", "782")
      .replace("{s}", "a")
      .replace("{r}", "");
    return "background-image:url('" + url + "')";
  }

  function drawerLayersMarkup() {
    var basemaps = state.controller.basemaps;
    var overlayDefs = LDCW.mapLayers ? LDCW.mapLayers.OVERLAY_DEFS : [];

    var styles = !basemaps
      ? ""
      : '<div class="drawer__group"><h3 class="drawer__title" id="explore-style-label">Map style</h3>' +
        '<div class="style-grid" role="radiogroup" aria-labelledby="explore-style-label">' +
        basemaps.defs
          .map(function (def) {
            return (
              '<button type="button" class="style-swatch" role="radio" aria-checked="' +
              (def.key === basemaps.active() ? "true" : "false") +
              '" data-basemap="' +
              def.key +
              '" title="' +
              escape(def.hint || "") +
              '"><span class="style-swatch__chip" style="' +
              swatchStyle(def) +
              '" aria-hidden="true"></span><span>' +
              escape(def.label) +
              "</span></button>"
            );
          })
          .join("") +
        "</div></div>";

    var overlays = !overlayDefs.length
      ? ""
      : '<div class="drawer__group"><h3 class="drawer__title">Overlays</h3>' +
        overlayDefs
          .map(function (def) {
            return (
              '<label class="switch-row"><input type="checkbox" data-overlay="' +
              def.key +
              '"' +
              (state.controller.overlayEnabled(def.key) ? " checked" : "") +
              '><span class="switch-row__track" aria-hidden="true"></span>' +
              '<span class="switch-row__text"><strong>' +
              escape(def.label) +
              "</strong><span>" +
              escape(def.hint || "") +
              "</span></span></label>"
            );
          })
          .join("") +
        "</div>";

    var districts =
      '<div class="drawer__group"><h3 class="drawer__title">District</h3>' +
      '<label class="visually-hidden" for="explore-district">Filter to one election district</label>' +
      '<select class="input" id="explore-district"></select></div>';

    return styles + overlays + districts;
  }

  function drawerMenuMarkup() {
    var nav = (LDCW.NAV || []).map(function (item) {
      return (
        '<li><a href="' +
        item.href +
        '"' +
        (item.href === "explore.html" ? ' aria-current="page"' : "") +
        ">" +
        escape(item.label) +
        "</a></li>"
      );
    });
    nav.unshift('<li><a href="index.html">Home</a></li>');

    var demo = Store.isDemo
      ? '<div class="drawer__group"><h3 class="drawer__title">Demo mode</h3>' +
        '<p style="font-size:var(--text-sm);color:var(--text-on-ink-muted);line-height:1.5;margin:0">' +
        "The community reports on this map are illustrative samples, not real submissions, and " +
        "anything you submit is saved only in this browser. " +
        '<a href="about.html#demo-mode" style="color:var(--teal-bright)">How to connect a live database</a>.' +
        "</p></div>"
      : "";

    return (
      '<div class="drawer__group"><ul class="drawer__nav">' +
      nav.join("") +
      "</ul></div>" +
      demo +
      '<div class="drawer__group"><h3 class="drawer__title">About this map</h3>' +
      '<p style="font-size:var(--text-xs);color:var(--text-on-ink-muted);line-height:1.6;margin:0">' +
      "An independent community project. Not affiliated with, endorsed by or operated by Loudoun " +
      "County government, Erin Brockovich, or any data center owner or operator. Community reports " +
      "are unverified first-hand accounts, not findings of fact. Community report pins are offset " +
      "from the address given so the map never identifies a household. " +
      "Facility data © Loudoun County GIS." +
      "</p></div>"
    );
  }

  function openDrawer(which) {
    closeDrawer();
    state.drawer = which;

    var scrim = document.createElement("div");
    scrim.className = "explore__scrim";
    scrim.addEventListener("click", closeDrawer);

    var drawer = document.createElement("div");
    drawer.className = "drawer glass";
    drawer.id = "explore-drawer";
    drawer.setAttribute("role", "dialog");
    drawer.setAttribute("aria-modal", "true");
    drawer.setAttribute("aria-label", which === "layers" ? "Map style and overlays" : "Site menu");
    drawer.innerHTML =
      '<div class="drawer__head"><h2>' +
      (which === "layers" ? "Map &amp; layers" : "Loudoun Data Center Watch") +
      '</h2><button class="explore-btn" type="button" data-close>' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">' +
      '<path d="M18 6 6 18M6 6l12 12"/></svg><span class="visually-hidden">Close</span></button></div>' +
      '<div class="drawer__body">' +
      (which === "layers" ? drawerLayersMarkup() : drawerMenuMarkup()) +
      "</div>";

    els.root.appendChild(scrim);
    els.root.appendChild(drawer);
    els.drawer = drawer;
    els.scrim = scrim;

    drawer.querySelector("[data-close]").addEventListener("click", closeDrawer);
    if (which === "layers") bindDrawerLayers(drawer);

    (which === "layers" ? els.layersBtn : els.menuBtn).setAttribute("aria-expanded", "true");

    var first = drawer.querySelector("button, select, input, a");
    if (first) first.focus();
  }

  function closeDrawer() {
    if (els.drawer && els.drawer.parentNode) els.drawer.parentNode.removeChild(els.drawer);
    if (els.scrim && els.scrim.parentNode) els.scrim.parentNode.removeChild(els.scrim);
    els.drawer = null;
    els.scrim = null;

    if (state.drawer) {
      var button = state.drawer === "layers" ? els.layersBtn : els.menuBtn;
      button.setAttribute("aria-expanded", "false");
      button.focus();
    }
    state.drawer = null;
  }

  function bindDrawerLayers(drawer) {
    var basemaps = state.controller.basemaps;

    drawer.querySelectorAll("[data-basemap]").forEach(function (button) {
      button.addEventListener("click", function () {
        var def = basemaps.select(button.getAttribute("data-basemap"));
        if (!def) return;
        drawer.querySelectorAll("[data-basemap]").forEach(function (other) {
          other.setAttribute("aria-checked", String(other === button));
        });
        writeUrl();
      });
    });

    drawer.querySelectorAll("[data-overlay]").forEach(function (input) {
      input.addEventListener("change", function () {
        var key = input.getAttribute("data-overlay");
        if (input.checked) say("Loading " + key + "…");
        state.controller
          .setOverlay(key, input.checked, function (error) {
            input.checked = false;
            say("Could not load that overlay: " + error.message, true);
          })
          .then(function () {
            if (input.checked && state.controller.overlayEnabled(key)) say("");
            writeUrl();
          });
      });
    });

    var select = drawer.querySelector("#explore-district");
    if (select) {
      LDCW.ui.fillLocalitySelect(select, "Every district");
      select.value = (state.filter && state.filter.locality) || "";
      select.addEventListener("change", function () {
        state.filter = Object.assign({}, state.filter);
        if (select.value) state.filter.locality = select.value;
        else delete state.filter.locality;
        state.controller.setFilter(state.filter);
        renderList();
        writeUrl();
      });
    }
  }

  /* ---- Rail --------------------------------------------------------------- */

  function bindRail() {
    var tools = LDCW.mapTools;
    var map = state.controller.map;

    function pressed(act, on) {
      var button = els.rail.querySelector('[data-act="' + act + '"]');
      if (button) button.setAttribute("aria-pressed", String(on));
    }

    /* measureTool only ever assigns to `readout.textContent`. The status pill
       is hidden until it has something to say, so hand the tool a stand-in
       that routes those assignments through say() rather than letting it
       write into an element nobody can see. */
    var measureReadout = {
      set textContent(value) {
        say(value);
      },
      get textContent() {
        return els.status ? els.status.textContent : "";
      },
    };

    var measure = tools ? tools.measureTool(map, measureReadout) : null;
    var rings = tools
      ? tools.radiusTool(map, {
          onArm: function () {
            say("Tap the map to drop the rings.");
          },
          onDrop: function (latlng, radii) {
            var inside = radii.map(function (metres) {
              return state.controller.countWithin(latlng.lat, latlng.lng, metres);
            });
            say(
              rings.rings
                .map(function (miles, i) {
                  return (
                    miles +
                    " mi: " +
                    inside[i].facilities +
                    (inside[i].facilities === 1 ? " facility" : " facilities") +
                    ", " +
                    inside[i].reports +
                    (inside[i].reports === 1 ? " report" : " reports")
                  );
                })
                .join("  ·  ")
            );
            pressed("radius", false);
          },
          onClear: function () {
            say("");
          },
        })
      : null;
    state.rings = rings;

    els.rail.addEventListener("click", function (event) {
      var button = event.target.closest("[data-act]");
      if (!button) return;
      var act = button.getAttribute("data-act");

      if (act === "zoom-in") map.zoomIn();
      else if (act === "zoom-out") map.zoomOut();
      else if (act === "locate") {
        say("Asking your browser for your location…");
        tools.locate(map, function (error) {
          if (error) {
            say(error.message, true);
            return;
          }
          var centre = map.getCenter();
          var near = state.controller.countWithin(centre.lat, centre.lng, M_PER_MILE * 2);
          say(
            "Within two miles of you: " +
              near.facilities +
              (near.facilities === 1 ? " facility" : " facilities") +
              " and " +
              near.reports +
              (near.reports === 1 ? " report" : " reports") +
              "."
          );
        });
      } else if (act === "measure") {
        if (rings && rings.centre()) rings.clear();
        pressed("radius", false);
        var measuring = measure.toggle();
        pressed("measure", measuring);
        say(measuring ? "Tap two or more points to measure. Tap again to finish." : "");
      } else if (act === "radius") {
        if (measure) measure.clear();
        pressed("measure", false);
        pressed("radius", rings.toggle());
      } else if (act === "share") {
        share();
      }
    });
  }

  function share() {
    var url = window.location.origin + currentUrl();

    // navigator.share is the right thing on a phone and does not exist on most
    // desktops; the clipboard is the fallback, and a visible URL is the
    // fallback to the fallback (an insecure origin has neither API).
    if (navigator.share) {
      navigator.share({ title: "Loudoun Data Center Watch", url: url }).catch(function () {});
      return;
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard
        .writeText(url)
        .then(function () {
          say("Link to this view copied.");
        })
        .catch(function () {
          say(url);
        });
      return;
    }
    say(url);
  }

  /* ---- Search ------------------------------------------------------------- */

  function bindSearch() {
    var tools = LDCW.mapTools;
    if (!tools) return;

    els.search.addEventListener("submit", function (event) {
      event.preventDefault();
      var query = els.searchInput.value.trim();
      if (query.length < 3) {
        say("Type a few more characters.", true);
        return;
      }

      say("Searching…");
      els.searchResults.hidden = true;

      tools
        .geocode(query)
        .then(function (matches) {
          if (!matches.length) {
            say("No match inside Loudoun County. Try adding the town.", true);
            return;
          }
          say("");
          els.searchResults.innerHTML = matches
            .map(function (match, index) {
              return (
                '<button type="button" data-index="' +
                index +
                '">' +
                escape(match.label) +
                "</button>"
              );
            })
            .join("");
          els.searchResults.hidden = false;

          els.searchResults.querySelectorAll("button").forEach(function (button) {
            button.addEventListener("click", function () {
              var match = matches[Number(button.getAttribute("data-index"))];
              state.controller.focus(match.lat, match.lng, 14);
              els.searchResults.hidden = true;
              els.searchInput.value = match.label;

              var near = state.controller.countWithin(match.lat, match.lng, M_PER_MILE);
              say(
                "Within a mile of there: " +
                  near.facilities +
                  (near.facilities === 1 ? " facility" : " facilities") +
                  " and " +
                  near.reports +
                  (near.reports === 1 ? " report" : " reports") +
                  "."
              );
            });
          });
        })
        .catch(function (error) {
          say(error.message, true);
        });
    });

    document.addEventListener("click", function (event) {
      if (!els.search.contains(event.target)) els.searchResults.hidden = true;
    });
  }

  /* ---- Boot --------------------------------------------------------------- */

  function boot() {
    els.root = document.getElementById("explore");
    if (!els.root) return;

    els.chips = document.getElementById("explore-chips");
    els.rail = document.getElementById("explore-rail");
    els.status = document.getElementById("explore-status");
    els.sheet = document.getElementById("explore-sheet");
    els.grip = document.getElementById("explore-grip");
    els.sheetTitle = document.getElementById("explore-sheet-title");
    els.sheetSub = document.getElementById("explore-sheet-sub");
    els.sheetClose = document.getElementById("explore-sheet-close");
    els.list = document.getElementById("explore-list");
    els.layersBtn = document.getElementById("explore-layers-btn");
    els.menuBtn = document.getElementById("explore-menu-btn");
    els.search = document.getElementById("explore-search");
    els.searchInput = document.getElementById("explore-q");
    els.searchResults = document.getElementById("explore-results");

    var url = readUrl();
    state.filter = url.filter || {};

    var controller = LDCW.map.createMap("explore-map", {
      basemap: url.base || "dark",
      ariaLabel:
        "Full-screen map of Loudoun County data centers and community reports. " +
        "Everything shown here is also listed as text in the panel, and on the reports and statistics pages.",
      // The document pages open a full-page overlay for a report and a Leaflet
      // bubble for a facility. Here the panel already IS the detail view, so
      // both go there — one sheet, never two stacked on a phone.
      onFacilitySelect: function (facility) {
        select("facility", facility.id, { fly: false });
      },
      onReportSelect: function (report) {
        select("report", report.id, { fly: false });
      },
    });
    if (!controller) return;
    state.controller = controller;

    renderChips();
    setSnap(isDesktop() ? "full" : "peek");
    bindSheetDrag();
    bindRail();
    bindSearch();

    els.layersBtn.addEventListener("click", function () {
      if (state.drawer === "layers") closeDrawer();
      else openDrawer("layers");
    });
    els.menuBtn.addEventListener("click", function () {
      if (state.drawer === "menu") closeDrawer();
      else openDrawer("menu");
    });
    els.sheetClose.addEventListener("click", backToList);

    document.addEventListener("keydown", function (event) {
      if (event.key !== "Escape") return;
      if (state.drawer) closeDrawer();
      else if (state.mode === "detail") backToList();
    });

    // Restore the camera before the data lands, so the reader never sees the
    // county view snap to the shared position a moment later.
    if (url.centre) {
      controller.map.setView(url.centre, url.zoom || controller.map.getZoom(), { animate: false });
    } else if (url.zoom) {
      controller.map.setZoom(url.zoom, { animate: false });
    }

    if (url.layers) {
      ALL_LAYERS.forEach(function (key) {
        var on = url.layers.indexOf(key) !== -1;
        controller.setLayerVisible(key, on);
        setChip(key, on);
      });
    }

    controller.setFilter(state.filter);

    controller.map.on("moveend zoomend", function () {
      renderList();
      writeUrl();
    });

    window.addEventListener("resize", function () {
      setSnap(state.snap);
    });

    // The count line is set in Archivo and IBM Plex Mono. Until those land the
    // peek strip is measured against the fallbacks and comes out a few pixels
    // short, which leaves a sliver of the first row showing under it.
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(function () {
        setSnap(state.snap);
      });
    }

    Promise.all([
      Store.loadFacilities().catch(function (error) {
        console.error("Facility layer failed to load", error);
        say("The facility layer didn't load. If you opened this file directly, serve the folder over HTTP.", true);
        return [];
      }),
      Store.listApproved({}).catch(function (error) {
        console.error("Reports failed to load", error);
        return [];
      }),
    ]).then(function (results) {
      state.facilities = results[0];
      state.reports = results[1];
      controller.setFacilities(state.facilities);
      controller.setReports(state.reports);
      renderList();

      if (url.overlays) {
        url.overlays.forEach(function (key) {
          controller.setOverlay(key, true, function () {});
        });
      }

      // On a phone the sheet starts collapsed so the reader sees the map
      // first, but the counts in the peek strip need to be real from the
      // outset or the strip reads as broken.
      if (!isDesktop() && !reduced()) {
        els.sheet.animate(
          [{ transform: "translateY(12px)", opacity: 0.6 }, { transform: "none", opacity: 1 }],
          { duration: 420, easing: "cubic-bezier(0.16,1,0.3,1)" }
        );
      }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})(window.LDCW);
