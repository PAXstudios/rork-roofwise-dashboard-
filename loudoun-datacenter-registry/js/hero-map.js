/*
 * The hero county figure.
 *
 * Builds an SVG of Loudoun County from data/county.json (the county's own
 * district boundaries) and drops the 224 real facility locations onto it,
 * projected with the same transform the Python build script used.
 *
 * The sequence: the county outline draws itself, the districts wash in, then
 * the facility dots land ordered EAST TO WEST — so the viewer watches Data
 * Center Alley fill up first and the rural west stay empty. That ordering is
 * the whole point of the animation; it makes the concentration legible in a
 * way a static dot map does not.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var motion = LDCW.motion;
  var schema = LDCW.schema;

  var SVG_NS = "http://www.w3.org/2000/svg";

  function el(name, attrs) {
    var node = document.createElementNS(SVG_NS, name);
    Object.keys(attrs || {}).forEach(function (key) {
      node.setAttribute(key, attrs[key]);
    });
    return node;
  }

  /* Mirrors Projection.point() in scripts/build-county-svg.py. */
  function makeProjector(projection) {
    return function (lng, lat) {
      return [
        (lng - projection.minLng) * projection.cosLat * projection.scale + projection.padding,
        (projection.maxLat - lat) * projection.scale + projection.padding,
      ];
    };
  }

  function render(container, county, facilities) {
    var reduced = motion.prefersReducedMotion();
    var project = makeProjector(county.projection);

    var svg = el("svg", {
      viewBox: county.viewBox,
      role: "img",
      "aria-label":
        "Map of Loudoun County's eight districts showing " +
        facilities.length +
        " data center parcels, concentrated in the east of the county.",
    });

    // ---- Districts -------------------------------------------------------
    var districtGroup = el("g", {});
    county.districts.forEach(function (district, index) {
      var path = el("path", {
        d: district.d,
        class: "hero-figure__district",
      });
      path.style.setProperty("--stagger-index", String(index));
      districtGroup.appendChild(path);
    });
    svg.appendChild(districtGroup);

    // ---- County outline, drawn as one continuous stroke -------------------
    var outline = el("path", {
      d: county.outline,
      class: "hero-figure__outline",
    });
    svg.appendChild(outline);

    // ---- Facility dots, east to west --------------------------------------
    var dotGroup = el("g", {});
    var sorted = facilities.slice().sort(function (a, b) {
      return b.lng - a.lng; // east (less negative) first
    });

    sorted.forEach(function (facility, index) {
      if (!isFinite(facility.lat) || !isFinite(facility.lng)) return;
      var point = project(facility.lng, facility.lat);
      var dot = el("circle", {
        cx: point[0].toFixed(1),
        cy: point[1].toFixed(1),
        r: facility.status === "operational" ? 5.5 : 4.5,
        class: "hero-figure__dot hero-figure__dot--" + facility.status,
        "fill-opacity": "0.85",
      });
      dot.style.setProperty("--stagger-index", String(index));
      dotGroup.appendChild(dot);
    });
    svg.appendChild(dotGroup);

    // ---- District labels, only the ones with room -------------------------
    var labelGroup = el("g", {});
    county.districts.forEach(function (district, index) {
      var label = el("text", {
        x: district.labelX,
        y: district.labelY,
        class: "hero-figure__label",
      });
      label.textContent = district.name;
      label.style.setProperty("--stagger-index", String(index));
      labelGroup.appendChild(label);
    });
    svg.appendChild(labelGroup);

    container.innerHTML = "";
    container.appendChild(svg);

    // ---- Kick off the draw-on --------------------------------------------
    // getTotalLength has to be measured after the path is in the document.
    if (!reduced && typeof outline.getTotalLength === "function") {
      var length = outline.getTotalLength();
      outline.style.strokeDasharray = length;
      outline.style.strokeDashoffset = length;
      // Force layout so the dasharray is committed before the animation class
      // takes effect, otherwise the browser may batch them and skip the draw.
      void outline.getBoundingClientRect();
      outline.style.animationName = "draw-path";
    }

    return svg;
  }

  function caption(container, facilities, summary) {
    if (!container) return;

    var counts = { operational: 0, under_construction: 0, proposed: 0 };
    facilities.forEach(function (facility) {
      if (counts[facility.status] != null) counts[facility.status] += 1;
    });

    container.innerHTML =
      "<strong>" +
      schema.formatNumber(facilities.length) +
      " data center parcels in Loudoun County</strong> — " +
      schema.formatNumber(counts.operational) +
      " operational, " +
      schema.formatNumber(counts.under_construction) +
      " under construction, " +
      schema.formatNumber(counts.proposed) +
      " in the approval pipeline. Source: Loudoun County GIS" +
      (summary && summary.generated
        ? ", " + schema.formatDate(summary.generated)
        : "") +
      ".";
  }

  function init() {
    var container = document.getElementById("hero-figure");
    if (!container) return;

    Promise.all([
      Store.loadJson("data/county.json"),
      Store.loadFacilities(),
      Store.loadSummary().catch(function () {
        return null;
      }),
    ])
      .then(function (results) {
        render(container, results[0], results[1]);
        caption(document.getElementById("hero-figure-caption"), results[1], results[2]);
      })
      .catch(function (error) {
        // The hero is decoration; the headline beside it carries the message.
        // Failing quietly beats showing a broken frame.
        console.warn("Hero figure unavailable", error);
        container.remove();
      });
  }

  LDCW.heroMap = { init: init };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})(window.LDCW);
