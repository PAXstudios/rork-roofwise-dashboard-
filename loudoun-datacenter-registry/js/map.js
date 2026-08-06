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
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var schema = LDCW.schema;

  function config() {
    return window.LDCW_CONFIG || {};
  }

  /* ---- Markers ------------------------------------------------------------ */

  function facilityIcon(status) {
    var size = status === "operational" ? 12 : 11;
    return L.divIcon({
      className: "",
      html: '<span class="pin pin--' + status + '"></span>',
      iconSize: [size, size],
      iconAnchor: [size / 2, size / 2],
    });
  }

  function reportIcon() {
    return L.divIcon({
      className: "",
      html: '<span class="pin pin--report"></span>',
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

    if (facility.operator) {
      rows.push(["Property owner", escape(facility.operator)]);
    }
    if (facility.district) {
      rows.push(["District", escape(facility.district)]);
    }
    var sqft = schema.formatSqft(facility.sqft);
    if (sqft) {
      rows.push(["Floor area", escape(sqft)]);
    }
    if (facility.acres) {
      rows.push(["Parcel", escape(facility.acres + " acres")]);
    }
    if (facility.zoning) {
      rows.push(["Zoning", escape(facility.zoning)]);
    }
    if (facility.zoning_case) {
      rows.push(["Case", escape(facility.zoning_case)]);
    }
    if (facility.application) {
      rows.push(["Application", escape(facility.application)]);
    }
    if (facility.status_raw) {
      rows.push(["County status", escape(facility.status_raw)]);
    }

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

  /**
   * @param {string} elementId    id of the map container
   * @param {object} options
   *   - interactiveReports {boolean} render the community report layer
   *   - onReady {function}          called with the controller once tiles exist
   */
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
    });

    // Screen readers announce the container; the sighted-user equivalent is the
    // list rendered underneath every map on the site.
    element.setAttribute("role", "application");
    element.setAttribute(
      "aria-label",
      options.ariaLabel ||
        "Map of Loudoun County data centers and community reports. An equivalent list follows below."
    );

    L.tileLayer(settings.TILE_URL, {
      attribution: settings.TILE_ATTRIBUTION,
      maxZoom: 19,
    }).addTo(map);

    var layers = {
      operational: L.markerClusterGroup({
        iconCreateFunction: clusterIconFactory("facilities"),
        maxClusterRadius: 45,
        showCoverageOnHover: false,
      }),
      under_construction: L.markerClusterGroup({
        iconCreateFunction: clusterIconFactory("facilities"),
        maxClusterRadius: 45,
        showCoverageOnHover: false,
      }),
      proposed: L.markerClusterGroup({
        iconCreateFunction: clusterIconFactory("facilities"),
        maxClusterRadius: 45,
        showCoverageOnHover: false,
      }),
      reports: L.markerClusterGroup({
        iconCreateFunction: clusterIconFactory("reports"),
        maxClusterRadius: 35,
        showCoverageOnHover: false,
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
    };

    function clearAll() {
      Object.keys(layers).forEach(function (key) {
        layers[key].clearLayers();
      });
    }

    function render() {
      clearAll();

      var counts = { operational: 0, under_construction: 0, proposed: 0, reports: 0 };

      state.facilities.forEach(function (facility) {
        if (!isFinite(facility.lat) || !isFinite(facility.lng)) return;
        var status = facility.status;
        if (!layers[status]) return;
        if (!schema.matchesFacilityFilter(facility, state.filter)) return;

        counts[status] += 1;
        if (!state.visible[status]) return;

        var marker = L.marker([facility.lat, facility.lng], {
          icon: facilityIcon(status),
          keyboard: true,
          alt: (facility.name || "Data center") + " — " + schema.statusLabel(status),
        });
        marker.bindPopup(facilityPopup(facility), { maxWidth: 320 });
        layers[status].addLayer(marker);
      });

      state.reports.forEach(function (report) {
        if (!isFinite(report.lat) || !isFinite(report.lng)) return;
        if (!schema.matchesFilter(report, state.filter)) return;

        counts.reports += 1;
        if (!state.visible.reports) return;

        var marker = L.marker([report.lat, report.lng], {
          icon: reportIcon(),
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
      });

      state.counts = counts;
      updateToggleCounts();
      element.dispatchEvent(
        new CustomEvent("ldcw:mapcounts", { detail: counts, bubbles: true })
      );
    }

    function updateToggleCounts() {
      Object.keys(state.counts).forEach(function (key) {
        var node = document.querySelector('[data-layer-count="' + key + '"]');
        if (node) node.textContent = schema.formatNumber(state.counts[key]);
      });
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

    /* ---- Controller ------------------------------------------------------- */

    var controller = {
      map: map,
      layers: layers,

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
        state.filter = filter || {};
        render();
        return controller;
      },

      getCounts: function () {
        return Object.assign({}, state.counts);
      },

      bindToggles: bindToggles,

      focus: function (lat, lng, zoom) {
        map.setView([lat, lng], zoom || 15);
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
        if (points.length) {
          map.fitBounds(L.latLngBounds(points).pad(0.15));
        }
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

  LDCW.map = {
    createMap: createMap,
    renderLayerToggles: renderLayerToggles,
    LAYER_DEFS: LAYER_DEFS,
  };
})(window.LDCW);
