/*
 * The hero: twenty years of Loudoun County, in about twelve seconds.
 *
 * The county publishes the date every data center application was filed. Join
 * that to the parcels and you get the actual chronology — one application in
 * 2005, thirty-one in 2024 — and the clearest single statement of what
 * happened here is simply to play it back and let someone watch the corridor
 * fill in.
 *
 * Nothing here is estimated. 160 of the 224 parcels carry a date the county
 * itself published; the rest have no matching case record and are shown in a
 * final undated pass rather than being given a plausible-looking year.
 *
 * The playback is scrubbable, pausable, and skipped entirely under
 * prefers-reduced-motion — where it renders its own end state, which is the
 * complete map. A reader who can't take motion should get the finished
 * picture, not an empty one.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var motion = LDCW.motion;
  var schema = LDCW.schema;

  var SVG_NS = "http://www.w3.org/2000/svg";
  var YEAR_MS = 620; // dwell per year at normal speed

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

  function build(container, county, facilities) {
    var project = makeProjector(county.projection);
    var reduced = motion.prefersReducedMotion();

    var dated = facilities.filter(function (f) {
      return f.applied_year;
    });
    var undated = facilities.filter(function (f) {
      return !f.applied_year;
    });

    var years = dated.map(function (f) {
      return f.applied_year;
    });
    var firstYear = Math.min.apply(null, years);
    var lastYear = Math.max.apply(null, years);

    /* ---- Figure --------------------------------------------------------- */

    var svg = el("svg", {
      viewBox: county.viewBox,
      class: "hero-fig__svg",
      role: "img",
      "aria-label":
        "Loudoun County. " +
        facilities.length +
        " data center parcels appear in the order they were applied for, from " +
        firstYear +
        " to " +
        lastYear +
        ", concentrated along the eastern edge of the county.",
    });

    var defs = el("defs", {});
    // A soft radial wash behind the corridor — the "heat" of the thing.
    var glow = el("radialGradient", { id: "hero-heat", cx: "0.74", cy: "0.56", r: "0.42" });
    [
      ["0%", "var(--signal-bright)", "0.34"],
      ["45%", "var(--amber-bright)", "0.16"],
      ["100%", "var(--teal-bright)", "0"],
    ].forEach(function (stop) {
      glow.appendChild(
        el("stop", { offset: stop[0], "stop-color": stop[1], "stop-opacity": stop[2] })
      );
    });
    defs.appendChild(glow);
    svg.appendChild(defs);

    svg.appendChild(
      el("rect", {
        x: 0, y: 0, width: "100%", height: "100%",
        fill: "url(#hero-heat)", class: "hero-fig__heat",
      })
    );

    var districtGroup = el("g", { class: "hero-fig__districts" });
    county.districts.forEach(function (district, index) {
      var path = el("path", { d: district.d, class: "hero-fig__district" });
      path.style.setProperty("--stagger-index", String(index));
      districtGroup.appendChild(path);
    });
    svg.appendChild(districtGroup);

    var outline = el("path", { d: county.outline, class: "hero-fig__outline" });
    svg.appendChild(outline);

    var dotGroup = el("g", { class: "hero-fig__dots" });
    svg.appendChild(dotGroup);

    /* One node per parcel, all created up front and revealed by class. Adding
       and removing 224 SVG nodes on every scrub would thrash layout; toggling
       a class does not. */
    var nodes = [];
    facilities.forEach(function (facility) {
      var point = project(facility.lng, facility.lat);
      var dot = el("circle", {
        cx: point[0].toFixed(1),
        cy: point[1].toFixed(1),
        r: facility.status === "operational" ? 4.6 : 4,
        class: "hero-fig__dot hero-fig__dot--" + facility.status,
      });
      dotGroup.appendChild(dot);
      nodes.push({ node: dot, year: facility.applied_year || null, facility: facility });
    });

    container.appendChild(svg);

    /* ---- Readout -------------------------------------------------------- */

    var readout = document.createElement("div");
    readout.className = "hero-fig__readout";
    readout.innerHTML =
      '<div class="hero-fig__year" aria-hidden="true"><span data-year>' +
      firstYear +
      "</span></div>" +
      '<div class="hero-fig__tally">' +
      '<span class="hero-fig__count" data-count>0</span>' +
      '<span class="hero-fig__unit">parcels applied for<br>by <span data-year-inline>' +
      firstYear +
      "</span></span>" +
      "</div>";
    container.appendChild(readout);

    var controls = document.createElement("div");
    controls.className = "hero-fig__controls";
    controls.innerHTML =
      '<button type="button" class="hero-fig__play" data-play aria-label="Pause the timeline">' +
      '<span data-play-icon>&#10073;&#10073;</span></button>' +
      '<label class="visually-hidden" for="hero-scrub">Year</label>' +
      '<input class="hero-fig__scrub" id="hero-scrub" type="range" min="' +
      firstYear +
      '" max="' +
      lastYear +
      '" step="1" value="' +
      firstYear +
      '" aria-valuetext="' + firstYear + '">' +
      '<span class="hero-fig__range"><span>' +
      firstYear +
      "</span><span>" +
      lastYear +
      "</span></span>";
    container.appendChild(controls);

    /* ---- Playback ------------------------------------------------------- */

    var yearNode = readout.querySelector("[data-year]");
    var yearInline = readout.querySelector("[data-year-inline]");
    var countNode = readout.querySelector("[data-count]");
    var scrub = controls.querySelector("[data-scrub], .hero-fig__scrub");
    var playButton = controls.querySelector("[data-play]");
    var playIcon = controls.querySelector("[data-play-icon]");

    var current = firstYear;
    var playing = false;
    var timer = null;

    function paint(year, opts) {
      opts = opts || {};
      var shown = 0;
      nodes.forEach(function (entry) {
        var visible = entry.year !== null && entry.year <= year;
        // The undated parcels only ever appear once playback has finished, so
        // they never imply a date the county did not publish.
        if (entry.year === null) visible = opts.includeUndated === true;
        if (visible) shown += 1;
        entry.node.classList.toggle("is-on", visible);
        // "Just arrived" drives a one-shot pulse; only while playing, so
        // scrubbing doesn't set 200 animations running at once.
        entry.node.classList.toggle(
          "is-new",
          Boolean(opts.animate) && entry.year === year
        );
      });

      yearNode.textContent = year;
      yearInline.textContent = year;
      countNode.textContent = schema.formatNumber(shown);
      if (scrub && Number(scrub.value) !== year) scrub.value = year;
      if (scrub) scrub.setAttribute("aria-valuetext", String(year));
      current = year;
    }

    function step() {
      if (!playing) return;
      if (current >= lastYear) {
        // Final pass: everything, including the parcels with no date.
        paint(lastYear, { includeUndated: true });
        stop();
        container.classList.add("is-complete");
        return;
      }
      paint(current + 1, { animate: true });
      timer = setTimeout(step, YEAR_MS);
    }

    function play() {
      if (current >= lastYear) {
        container.classList.remove("is-complete");
        paint(firstYear);
      }
      playing = true;
      playIcon.innerHTML = "&#10073;&#10073;";
      playButton.setAttribute("aria-label", "Pause the timeline");
      timer = setTimeout(step, YEAR_MS);
    }

    function stop() {
      playing = false;
      clearTimeout(timer);
      playIcon.innerHTML = "&#9654;";
      playButton.setAttribute("aria-label", "Play the timeline");
    }

    playButton.addEventListener("click", function () {
      if (playing) stop();
      else play();
    });

    scrub.addEventListener("input", function () {
      stop();
      var year = Number(scrub.value);
      paint(year, { includeUndated: year >= lastYear });
      container.classList.toggle("is-complete", year >= lastYear);
    });

    /* ---- Caption -------------------------------------------------------- */

    var caption = document.getElementById("hero-figure-caption");
    if (caption) {
      caption.innerHTML =
        "<strong>" +
        schema.formatNumber(facilities.length) +
        " data center parcels</strong>, shown in the order their applications were filed. " +
        schema.formatNumber(dated.length) +
        " carry a filing date published by the county; " +
        schema.formatNumber(undated.length) +
        " have no matching case record and appear at the end. " +
        "Source: Loudoun County GIS and the county's land-development plans layer.";
    }

    /* ---- Start ---------------------------------------------------------- */

    if (reduced) {
      // No motion: render the finished map immediately. Someone who can't
      // take animation should still get the whole picture.
      paint(lastYear, { includeUndated: true });
      container.classList.add("is-complete", "is-static");
      stop();
      return;
    }

    paint(firstYear);
    // Wait for the outline to finish drawing before the dots start landing;
    // two animations competing for attention reads as noise.
    setTimeout(function () {
      if (motion.isVisible ? motion.isVisible(container) : true) play();
      else play();
    }, 1500);

    // Pause when scrolled away — an animation nobody is watching is just
    // battery, and it should be at the start when they come back.
    if ("IntersectionObserver" in window) {
      var observer = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (!entry.isIntersecting && playing) stop();
          });
        },
        { threshold: 0.15 }
      );
      observer.observe(container);
    }
  }

  function init() {
    var container = document.getElementById("hero-figure");
    if (!container || !Store) return;

    Promise.all([
      Store.loadJson("data/county.json"),
      Store.loadFacilities(),
    ])
      .then(function (results) {
        build(container, results[0], results[1]);
      })
      .catch(function () {
        // The hero is decorative in the strict sense — every number it shows
        // appears again as text below. Failing quietly beats an error box.
        container.hidden = true;
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})(window.LDCW);
