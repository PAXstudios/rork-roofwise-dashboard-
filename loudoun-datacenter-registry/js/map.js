/*
 * The map.
 *
 * Four layers, matching the four things a visitor can be looking at:
 * operational facilities, facilities under construction, proposed facilities,
 * and community reports. Each has its own colour AND its own marker shape, so
 * the map stays readable without colour vision, and the legend spells both out.
 *
 * The map is never the only route to the data — every page that embeds one also
 * renders the same records as text below it.
 *
 * Motion: markers cascade in on first render, filtering to a single district
 * flies the camera there, and community-report pins carry a slow pulse because
 * they are the live, human part of the data. All of it defers to
 * prefers-reduced-motion via LDCW.motion.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var schema = LDCW.schema;

  function config() {
    return window.LDCW_CONFIG || {};
  }

  function reduced() {
    return LDCW.motion ? LDCW.motion.prefersReducedMotion() : false;
  }

  /* ---- Markers ------------------------------------------------------------ */

  /* `enterIndex` drives the staggered drop-in. Passing null skips it, which is
     what re-renders (a filter change) do — only the first paint cascades. */
  function facilityIcon(status, enterIndex) {
    var size = status === "operational" ? 12 : 11;
    var classes = "pin pin--" + status + (enterIndex == null ? "" : " pin--enter");
    var style = enterIndex == null ? "" : ' style="--stagger-index:' + enterIndex + '"';

    return L.divIcon({
      className: "",
      html: '<span class="' + classes + '"' + style + "></span>",
      iconSize: [size, size],
      iconAnchor: [size / 2, size / 2],
    });
  }

  function reportIcon(enterIndex) {
    var classes = "pin pin--report" + (enterIndex == null ? "" : " pin--enter");
    var style = enterIndex == null ? "" : ' style="--stagger-index:' + enterIndex + '"';

    return L.divIcon({
      className: "",
      html: '<span class="' + classes + '"' + style + "></span>",
      iconSize: [18, 18],
      iconAnchor: [9, 18],
      popupAnchor: [0, -14],
    });
  }

  function clusterIconFactory(variant) {
    return function (cluster) {
      var count = cluster.getChildCount();
      var size = count < 10 ? 34 : count < 100 ? 40 : 48;
      return L.divIcon({
        html: "<span>" + count + "</span>",
        className:
          "marker-cluster-custom" +
          (variant === "reports" ? " marker-cluster-custom--reports" : ""),
        iconSize: L.point(size, size),
      });
    };
  }

  /* ---- Popups ------------------------------------------------------------- */

  function facilityPopup(facility) {
    var escape = schema.escapeHtml;
    var rows = [];

    if (facility.operator) rows.push(["Property owner", escape(facility.operator)]);
    if (facility.district) rows.push(["District", escape(facility.district)]);

    var sqft = schema.formatSqft(facility.sqft);
    if (sqft) rows.push(["Floor area", escape(sqft)]);
    if (facility.acres) rows.push(["Parcel", escape(facility.acres + " acres")]);
    if (facility.zoning) rows.push(["Zoning", escape(facility.zoning)]);
    if (facility.zoning_case) rows.push(["Case", escape(facility.zoning_case)]);
    if (facility.application) rows.push(["Application", escape(facility.application)]);
    if (facility.status_raw) rows.push(["County status", escape(facility.status_raw)]);

    var meta = rows.length
      ? '<dl class="popup__meta">' +
        rows
          .map(function (pair) {
            return "<dt>" + pair[0] + "</dt><dd>" + pair[1] + "</dd>";
          })
          .join("") +
        "</dl>"
      : "";

    return (
      '<h3 class="popup__title">' +
      escape(facility.name || "Data center parcel") +
      "</h3>" +
      '<span class="badge badge--' +
      escape(facility.status) +
      '">' +
      escape(schema.statusLabel(facility.status)) +
      "</span>" +
      meta +
      '<p class="popup__source">Source: Loudoun County GIS. Ownership is the recorded ' +
      "property owner, which is often a holding company.</p>" +
      '<p class="popup__source"><a href="report.html">Report an issue near here</a></p>'
    );
  }

  function reportPopup(report) {
    var escape = schema.escapeHtml;

    var badges = (report.categories || [])
      .map(function (key) {
        return '<span class="badge badge--neutral">' + escape(schema.categoryLabel(key)) + "</span>";
      })
      .join("");

    var description = report.description || "";
    var truncated = description.length > 220 ? description.slice(0, 220).trim() + "…" : description;

    var demoNote = report.is_demo
      ? '<p class="popup__source"><strong>Sample report.</strong> Illustrative only — not a real submission.</p>'
      : "";

    return (
      '<h3 class="popup__title">' +
      escape(report.locality || "Loudoun County") +
      (report.zip ? " " + escape(report.zip) : "") +
      "</h3>" +
      '<div class="badge-list">' +
      badges +
      "</div>" +
      '<p class="popup__body">' +
      escape(truncated) +
      "</p>" +
      '<p class="popup__source">Reported ' +
      escape(schema.formatRelative(report.created_at)) +
      " · Impact " +
      escape(String(report.severity)) +
      "/5 · Location shown is approximate</p>" +
      demoNote
    );
  }

  /* ---- Map construction --------------------------------------------------- */

  function createMap(elementId, options) {
    options = options || {};
    var settings = config();
    var element = document.getElementById(elementId);
    if (!element) return null;

    var map = L.map(element, {
      center: settings.MAP_CENTER,
      zoom: settings.MAP_ZOOM,
      minZoom: settings.MAP_MIN_ZOOM,
      maxBounds: L.latLngBounds(settings.MAP_BOUNDS).pad(0.25),
      scrollWheelZoom: options.scrollWheelZoom !== false,
      zoomControl: true,
      // Leaflet's own easing for programmatic camera moves.
      zoomAnimation: !reduced(),
      fadeAnimation: !reduced(),
      markerZoomAnimation: !reduced(),
    });

    element.setAttribute("role", "application");
    element.setAttribute(
      "aria-label",
      options.ariaLabel ||
        "Map of Loudoun County data centers and community reports. An equivalent list follows below."
    );

    /* Basemaps. If map-layers.js isn't on the page — the hero and any future
       embed load a smaller script set — fall back to the single OSM layer, so
       a missing optional file degrades rather than breaks. */
    var basemaps = LDCW.mapLayers ? LDCW.mapLayers.buildBasemaps(map) : null;
    if (basemaps) {
      basemaps.select(options.basemap || "streets");
    } else {
      L.tileLayer(settings.TILE_URL, {
        attribution: settings.TILE_ATTRIBUTION,
        maxZoom: 19,
      }).addTo(map);
    }

    L.control.scale({ position: "bottomleft", imperial: true, metric: true }).addTo(map);

    var layers = {
      operational: L.markerClusterGroup({
        iconCreateFunction: clusterIconFactory("facilities"),
        maxClusterRadius: 45,
        showCoverageOnHover: false,
        animate: !reduced(),
      }),
      under_construction: L.markerClusterGroup({
        iconCreateFunction: clusterIconFactory("facilities"),
        maxClusterRadius: 45,
        showCoverageOnHover: false,
        animate: !reduced(),
      }),
      proposed: L.markerClusterGroup({
        iconCreateFunction: clusterIconFactory("facilities"),
        maxClusterRadius: 45,
        showCoverageOnHover: false,
        animate: !reduced(),
      }),
      reports: L.markerClusterGroup({
        iconCreateFunction: clusterIconFactory("reports"),
        maxClusterRadius: 35,
        showCoverageOnHover: false,
        animate: !reduced(),
      }),
    };

    Object.keys(layers).forEach(function (key) {
      if (key === "reports" && options.interactiveReports === false) return;
      layers[key].addTo(map);
    });

    var state = {
      facilities: [],
      reports: [],
      filter: {},
      visible: {
        operational: true,
        under_construction: true,
        proposed: true,
        reports: true,
      },
      counts: { operational: 0, under_construction: 0, proposed: 0, reports: 0 },
      // Only the very first paint cascades; later renders would look like a
      // glitch rather than an arrival.
      hasEntered: false,
      markersById: {},
    };

    function clearAll() {
      Object.keys(layers).forEach(function (key) {
        layers[key].clearLayers();
      });
      state.markersById = {};
    }

    function render() {
      clearAll();

      var animateEntry = !state.hasEntered && !reduced();
      var counts = { operational: 0, under_construction: 0, proposed: 0, reports: 0 };
      var entered = 0;

      state.facilities.forEach(function (facility) {
        if (!isFinite(facility.lat) || !isFinite(facility.lng)) return;
        var status = facility.status;
        if (!layers[status]) return;
        if (!schema.matchesFacilityFilter(facility, state.filter)) return;

        counts[status] += 1;
        if (!state.visible[status]) return;

        // Cap the cascade — beyond ~120 the tail is imperceptible and the
        // delay just makes the map feel slow to settle.
        var enterIndex = animateEntry && entered < 120 ? entered : null;
        entered += 1;

        var marker = L.marker([facility.lat, facility.lng], {
          icon: facilityIcon(status, enterIndex),
          keyboard: true,
          alt: (facility.name || "Data center") + " — " + schema.statusLabel(status),
        });
        marker.bindPopup(facilityPopup(facility), { maxWidth: 320 });
        layers[status].addLayer(marker);
      });

      state.reports.forEach(function (report, index) {
        if (!isFinite(report.lat) || !isFinite(report.lng)) return;
        if (!schema.matchesFilter(report, state.filter)) return;

        counts.reports += 1;
        if (!state.visible.reports) return;

        var marker = L.marker([report.lat, report.lng], {
          icon: reportIcon(animateEntry ? index : null),
          keyboard: true,
          alt:
            "Community report in " +
            (report.locality || "Loudoun County") +
            ", impact " +
            report.severity +
            " of 5",
        });
        marker.bindPopup(reportPopup(report), { maxWidth: 320 });
        layers.reports.addLayer(marker);
        state.markersById[report.id] = marker;
      });

      if (animateEntry && (entered > 0 || counts.reports > 0)) state.hasEntered = true;

      state.counts = counts;
      updateToggleCounts();
      refreshHeat();
      element.dispatchEvent(new CustomEvent("ldcw:mapcounts", { detail: counts, bubbles: true }));
    }

    function updateToggleCounts() {
      Object.keys(state.counts).forEach(function (key) {
        var node = document.querySelector('[data-layer-count="' + key + '"]');
        if (node) node.textContent = schema.formatNumber(state.counts[key]);
      });
    }

    /* ---- Camera ----------------------------------------------------------- */

    /* When a filter narrows to one district, fly there — otherwise the user has
       to hunt for the handful of remaining pins. Returning to "all" flies back
       to the county view. */
    function frameFilter(previousLocality) {
      var locality = state.filter.locality;
      if (locality === previousLocality) return;

      var points = [];
      state.facilities.forEach(function (facility) {
        if (!schema.matchesFacilityFilter(facility, state.filter)) return;
        if (isFinite(facility.lat)) points.push([facility.lat, facility.lng]);
      });
      state.reports.forEach(function (report) {
        if (!schema.matchesFilter(report, state.filter)) return;
        if (isFinite(report.lat)) points.push([report.lat, report.lng]);
      });

      if (!points.length) return;

      var bounds = L.latLngBounds(points).pad(0.2);
      if (reduced()) {
        map.fitBounds(bounds, { animate: false });
      } else {
        map.flyToBounds(bounds, { duration: 0.9, easeLinearity: 0.22 });
      }
    }

    /* ---- Layer toggles ---------------------------------------------------- */

    function bindToggles(container) {
      if (!container) return;
      container.querySelectorAll("input[data-layer]").forEach(function (input) {
        var key = input.getAttribute("data-layer");
        input.checked = state.visible[key] !== false;
        input.addEventListener("change", function () {
          state.visible[key] = input.checked;
          if (input.checked) {
            if (!map.hasLayer(layers[key])) map.addLayer(layers[key]);
          } else if (map.hasLayer(layers[key])) {
            map.removeLayer(layers[key]);
          }
          render();
        });
      });
    }

    /* ---- Overlays ----------------------------------------------------------
       Geometry is fetched on first toggle, not on load. The parcel outlines and
       building footprints are ~170 KB together and most visitors never turn
       them on; loading them eagerly was the single biggest thing slowing the
       first paint of this map. */

    var overlays = {};
    var overlayOn = {};
    var overlayPending = {};

    function heatPoints() {
      return state.reports
        .filter(function (report) {
          return (
            isFinite(report.lat) &&
            isFinite(report.lng) &&
            schema.matchesFilter(report, state.filter)
          );
        })
        .map(function (report) {
          return L.latLng(report.lat, report.lng);
        });
    }

    function setOverlay(key, on, onError) {
      overlayOn[key] = on;

      if (!on) {
        if (overlays[key] && map.hasLayer(overlays[key])) map.removeLayer(overlays[key]);
        return Promise.resolve();
      }

      if (overlays[key]) {
        overlays[key].addTo(map);
        return Promise.resolve();
      }

      if (key === "heat") {
        if (!LDCW.mapLayers) return Promise.resolve();
        overlays.heat = LDCW.mapLayers.heatLayer(heatPoints());
        overlays.heat.addTo(map);
        return Promise.resolve();
      }

      // Guard against a double-click queueing two fetches for the same file.
      if (overlayPending[key]) return overlayPending[key];

      var def = null;
      (LDCW.mapLayers ? LDCW.mapLayers.OVERLAY_DEFS : []).forEach(function (candidate) {
        if (candidate.key === key) def = candidate;
      });
      if (!def || !def.build) return Promise.resolve();

      overlayPending[key] = def
        .build()
        .then(function (layer) {
          overlays[key] = layer;
          delete overlayPending[key];
          // The reader may have toggled it back off while the fetch was in
          // flight. Respect the last thing they asked for, not the first.
          if (overlayOn[key]) layer.addTo(map);
          if (key === "parcels" || key === "buildings" || key === "districts") {
            layer.bringToBack();
          }
        })
        .catch(function (error) {
          delete overlayPending[key];
          overlayOn[key] = false;
          if (typeof onError === "function") onError(error);
        });

      return overlayPending[key];
    }

    function refreshHeat() {
      if (overlays.heat && overlayOn.heat) overlays.heat.setPoints(heatPoints());
    }

    /* ---- Controller ------------------------------------------------------- */

    var controller = {
      map: map,
      layers: layers,
      basemaps: basemaps,
      setOverlay: setOverlay,
      overlayEnabled: function (key) {
        return overlayOn[key] === true;
      },

      setFacilities: function (facilities) {
        state.facilities = facilities || [];
        render();
        return controller;
      },

      setReports: function (reports) {
        state.reports = reports || [];
        render();
        return controller;
      },

      setFilter: function (filter) {
        var previousLocality = state.filter ? state.filter.locality : undefined;
        state.filter = filter || {};
        render();
        frameFilter(previousLocality);
        return controller;
      },

      getCounts: function () {
        return Object.assign({}, state.counts);
      },

      /* What sits inside a circle. Used by the radius tool, and by "what's near
         me". Counts everything currently loaded, not just what the filter is
         showing — "three facilities within a mile" must not change because the
         reader happened to filter the map to one district. */
      countWithin: function (lat, lng, metres) {
        var origin = L.latLng(lat, lng);
        var result = { facilities: 0, reports: 0, byStatus: {} };

        state.facilities.forEach(function (facility) {
          if (!isFinite(facility.lat) || !isFinite(facility.lng)) return;
          if (origin.distanceTo(L.latLng(facility.lat, facility.lng)) > metres) return;
          result.facilities += 1;
          result.byStatus[facility.status] = (result.byStatus[facility.status] || 0) + 1;
        });

        state.reports.forEach(function (report) {
          if (!isFinite(report.lat) || !isFinite(report.lng)) return;
          if (origin.distanceTo(L.latLng(report.lat, report.lng)) > metres) return;
          result.reports += 1;
        });

        return result;
      },

      bindToggles: bindToggles,

      /* Bounce a report's pin — used when the reader hovers its card in the
         list, so the two views feel like one thing. */
      highlightReport: function (id) {
        var marker = state.markersById[id];
        if (!marker || reduced()) return;
        var icon = marker.getElement();
        var pin = icon && icon.querySelector(".pin");
        if (!pin) return;
        pin.classList.remove("pin--bounce");
        void pin.offsetWidth; // restart the animation
        pin.classList.add("pin--bounce");
      },

      focus: function (lat, lng, zoom) {
        if (reduced()) {
          map.setView([lat, lng], zoom || 15, { animate: false });
        } else {
          map.flyTo([lat, lng], zoom || 15, { duration: 0.8 });
        }
        return controller;
      },

      fitReports: function () {
        var points = state.reports
          .filter(function (report) {
            return isFinite(report.lat) && isFinite(report.lng);
          })
          .map(function (report) {
            return [report.lat, report.lng];
          });
        if (points.length) map.fitBounds(L.latLngBounds(points).pad(0.15));
        return controller;
      },

      invalidate: function () {
        map.invalidateSize();
        return controller;
      },
    };

    // Leaflet measures the container on creation; if it was hidden or the
    // layout shifted, re-measure once things settle.
    setTimeout(function () {
      map.invalidateSize();
    }, 200);

    // Several scripts on a page need the same map — the controls, the report
    // detail panel, the watchlist. With no module system, one shared handle
    // beats threading the controller through every init function.
    LDCW.map.current = controller;

    if (typeof options.onReady === "function") options.onReady(controller);

    return controller;
  }

  /* ---- Legend / toggle markup --------------------------------------------
     Rendered from one definition so the legend and the toggles can't disagree
     about what a shape means. */

  var LAYER_DEFS = [
    { key: "operational", label: "Operational", swatch: "operational" },
    { key: "under_construction", label: "Under construction", swatch: "under_construction" },
    { key: "proposed", label: "Proposed", swatch: "proposed" },
    { key: "reports", label: "Community reports", swatch: "report" },
  ];

  function renderLayerToggles(container, options) {
    if (!container) return;
    options = options || {};

    container.className = "layer-toggles";
    container.innerHTML = LAYER_DEFS.filter(function (def) {
      return !(def.key === "reports" && options.includeReports === false);
    })
      .map(function (def) {
        return (
          '<label class="layer-toggle">' +
          '<input type="checkbox" data-layer="' +
          def.key +
          '" checked>' +
          '<span class="legend__swatch legend__swatch--' +
          def.swatch +
          '" aria-hidden="true"></span>' +
          "<span>" +
          schema.escapeHtml(def.label) +
          "</span>" +
          '<span class="layer-toggle__count" data-layer-count="' +
          def.key +
          '">—</span>' +
          "</label>"
        );
      })
      .join("");
  }

  /* ---- Map controls -------------------------------------------------------
     Basemap, overlays and tools. Built as one panel rather than six Leaflet
     controls stacked over the map: on a phone, six floating buttons cover the
     thing you're trying to look at.

     Below 720px the whole panel collapses into a <details> sheet. <details> is
     used deliberately — it is keyboard operable, announces its state to screen
     readers, and survives with JavaScript disabled, none of which is true of a
     div with a click handler. */

  function renderMapControls(container, controller, options) {
    if (!container || !controller) return null;
    options = options || {};

    var tools = LDCW.mapTools;
    var basemaps = controller.basemaps;
    var overlayDefs = LDCW.mapLayers ? LDCW.mapLayers.OVERLAY_DEFS : [];

    var basemapMarkup = !basemaps
      ? ""
      : '<div class="map-controls__group">' +
        '<h3 class="map-controls__title" id="map-basemap-label">Base map</h3>' +
        '<div class="segmented" role="radiogroup" aria-labelledby="map-basemap-label">' +
        basemaps.defs
          .map(function (def, index) {
            return (
              '<button type="button" class="segmented__option" role="radio" ' +
              'aria-checked="' +
              (index === 0 ? "true" : "false") +
              '" data-basemap="' +
              def.key +
              '" title="' +
              schema.escapeHtml(def.hint || "") +
              '">' +
              schema.escapeHtml(def.label) +
              "</button>"
            );
          })
          .join("") +
        "</div></div>";

    var overlayMarkup = !overlayDefs.length
      ? ""
      : '<div class="map-controls__group">' +
        '<h3 class="map-controls__title">Overlays</h3>' +
        '<div class="overlay-toggles">' +
        overlayDefs
          .map(function (def) {
            return (
              '<label class="overlay-toggle">' +
              '<input type="checkbox" data-overlay="' +
              def.key +
              '"><span class="overlay-toggle__label">' +
              schema.escapeHtml(def.label) +
              '</span><span class="overlay-toggle__hint">' +
              schema.escapeHtml(def.hint || "") +
              "</span></label>"
            );
          })
          .join("") +
        "</div></div>";

    var toolsMarkup = !tools
      ? ""
      : '<div class="map-controls__group">' +
        '<h3 class="map-controls__title">Tools</h3>' +
        '<div class="map-tools">' +
        '<button type="button" class="btn btn--ghost btn--sm" data-tool="measure" aria-pressed="false">Measure</button>' +
        '<button type="button" class="btn btn--ghost btn--sm" data-tool="radius" aria-pressed="false">Radius rings</button>' +
        '<button type="button" class="btn btn--ghost btn--sm" data-tool="locate">Use my location</button>' +
        '<button type="button" class="btn btn--ghost btn--sm" data-tool="fullscreen" aria-pressed="false">Fullscreen</button>' +
        "</div>" +
        '<form class="map-search" role="search">' +
        '<label class="visually-hidden" for="map-address">Find an address in Loudoun County</label>' +
        '<input class="input" id="map-address" type="search" placeholder="Find an address…" autocomplete="street-address">' +
        '<button class="btn btn--secondary btn--sm" type="submit">Find</button>' +
        "</form>" +
        '<div class="map-search__results" hidden></div>' +
        "</div>";

    var body = basemapMarkup + overlayMarkup + toolsMarkup;

    container.className = "map-controls";
    container.innerHTML =
      '<details class="map-controls__sheet">' +
      "<summary>Map options</summary>" +
      '<div class="map-controls__body">' +
      body +
      "</div></details>" +
      '<p class="map-controls__readout" role="status" aria-live="polite"></p>';

    var readout = container.querySelector(".map-controls__readout");
    var sheet = container.querySelector(".map-controls__sheet");

    function say(message, isError) {
      readout.textContent = message || "";
      readout.classList.toggle("is-error", isError === true);
    }

    // Open by default on a wide screen, closed on a phone. Set once on load
    // rather than on resize: reopening a sheet the reader deliberately closed,
    // because they rotated their phone, is worse than the wrong default.
    if (sheet) sheet.open = window.innerWidth >= 720;

    /* ---- Basemap --------------------------------------------------------- */

    if (basemaps) {
      container.querySelectorAll("[data-basemap]").forEach(function (button) {
        button.addEventListener("click", function () {
          var def = basemaps.select(button.getAttribute("data-basemap"));
          if (!def) return;
          container.querySelectorAll("[data-basemap]").forEach(function (other) {
            other.setAttribute("aria-checked", String(other === button));
          });
          say(def.hint || "");
        });
      });
    }

    /* ---- Overlays -------------------------------------------------------- */

    container.querySelectorAll("[data-overlay]").forEach(function (input) {
      input.addEventListener("change", function () {
        var key = input.getAttribute("data-overlay");
        if (input.checked) say("Loading…");
        controller
          .setOverlay(key, input.checked, function (error) {
            input.checked = false;
            say("Could not load that overlay: " + error.message, true);
          })
          .then(function () {
            if (input.checked && controller.overlayEnabled(key)) say("");
          });
      });
    });

    /* ---- Tools ----------------------------------------------------------- */

    if (tools) {
      // Declared before the tools that call it. Block-scoped function
      // declarations do hoist in strict mode, but relying on that to call
      // something defined forty lines down is a favour to nobody.
      var setPressed = function (tool, on) {
        var button = container.querySelector('[data-tool="' + tool + '"]');
        if (button) button.setAttribute("aria-pressed", String(on));
      };

      var measure = tools.measureTool(controller.map, readout);
      var radius = tools.radiusTool(controller.map, {
        onArm: function () {
          say("Click the map to centre the rings.");
        },
        onDrop: function (latlng, radii) {
          var inside = radii.map(function (metres) {
            return controller.countWithin(latlng.lat, latlng.lng, metres);
          });
          say(
            radius.rings
              .map(function (miles, i) {
                return (
                  miles +
                  " mi: " +
                  inside[i].facilities +
                  " facilit" +
                  (inside[i].facilities === 1 ? "y" : "ies") +
                  ", " +
                  inside[i].reports +
                  " report" +
                  (inside[i].reports === 1 ? "" : "s")
                );
              })
              .join(" · ")
          );
          setPressed("radius", false);
        },
        onClear: function () {
          say("");
        },
      });

      container.querySelector('[data-tool="measure"]').addEventListener("click", function () {
        if (radius.centre()) radius.clear();
        setPressed("radius", false);
        setPressed("measure", measure.toggle());
      });

      container.querySelector('[data-tool="radius"]').addEventListener("click", function () {
        measure.clear();
        setPressed("measure", false);
        setPressed("radius", radius.toggle());
      });

      container.querySelector('[data-tool="locate"]').addEventListener("click", function () {
        say("Asking your browser for your location…");
        tools.locate(controller.map, function (error) {
          say(error ? error.message : "", Boolean(error));
        });
      });

      container.querySelector('[data-tool="fullscreen"]').addEventListener("click", function () {
        setPressed("fullscreen", tools.toggleFullscreen(controller.map));
      });

      /* ---- Address search ------------------------------------------------ */

      var form = container.querySelector(".map-search");
      var input = container.querySelector("#map-address");
      var results = container.querySelector(".map-search__results");

      form.addEventListener("submit", function (event) {
        event.preventDefault();
        var query = input.value.trim();
        if (query.length < 3) {
          say("Type a few more characters.", true);
          return;
        }

        say("Searching…");
        results.hidden = true;

        tools
          .geocode(query)
          .then(function (matches) {
            if (!matches.length) {
              say("No match inside Loudoun County. Try adding the town.", true);
              return;
            }
            say("");
            results.hidden = false;
            results.innerHTML = matches
              .map(function (match, index) {
                return (
                  '<button type="button" class="map-search__result" data-index="' +
                  index +
                  '">' +
                  schema.escapeHtml(match.label) +
                  "</button>"
                );
              })
              .join("");

            results.querySelectorAll(".map-search__result").forEach(function (button) {
              button.addEventListener("click", function () {
                var match = matches[Number(button.getAttribute("data-index"))];
                controller.focus(match.lat, match.lng, 15);
                radius.at(L.latLng(match.lat, match.lng));
                results.hidden = true;
                input.value = match.label;
              });
            });
          })
          .catch(function (error) {
            say(error.message, true);
          });
      });
    }

    if (typeof options.onReady === "function") options.onReady({ say: say });

    return { say: say };
  }

  LDCW.map = {
    createMap: createMap,
    renderLayerToggles: renderLayerToggles,
    renderMapControls: renderMapControls,
    LAYER_DEFS: LAYER_DEFS,
  };
})(window.LDCW);
