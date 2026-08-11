/*
 * Map tools: measure, radius rings, locate, fullscreen.
 *
 * Written directly against the Leaflet API rather than pulling in four more
 * plugins. Each of these is thirty to sixty lines, and vendoring four
 * dependencies to avoid writing them would be a worse trade for a site that
 * has no build step and ships its libraries in the repo.
 *
 * "How far is that from my house" is the question people arrive with, so the
 * measure and radius tools are the point of this file. Everything else is
 * supporting.
 */

(function (LDCW) {
  "use strict";

  var M_PER_MILE = 1609.344;
  var M_PER_FOOT = 0.3048;

  function config() {
    return window.LDCW_CONFIG || {};
  }

  function fmtDistance(metres) {
    var feet = metres / M_PER_FOOT;
    if (metres < 1000) {
      return Math.round(feet).toLocaleString() + " ft · " + Math.round(metres) + " m";
    }
    return (
      (metres / M_PER_MILE).toFixed(2) +
      " mi · " +
      (metres / 1000).toFixed(2) +
      " km"
    );
  }

  /* ---- Measure -----------------------------------------------------------
     Click to drop points, double-click or Escape to finish. The running total
     is shown in the readout as the pointer moves, which is what makes it feel
     like a tool rather than a form. */

  function measureTool(map, readout) {
    var points = [];
    var line = null;
    var preview = null;
    var dots = L.layerGroup();
    var active = false;

    function total(extra) {
      var metres = 0;
      for (var i = 1; i < points.length; i += 1) {
        metres += map.distance(points[i - 1], points[i]);
      }
      if (extra) metres += map.distance(points[points.length - 1], extra);
      return metres;
    }

    function say(message) {
      if (readout) readout.textContent = message;
    }

    function redraw(hover) {
      var path = hover ? points.concat([hover]) : points;
      if (path.length < 2) {
        if (preview) {
          map.removeLayer(preview);
          preview = null;
        }
        return;
      }
      if (!preview) {
        preview = L.polyline(path, {
          color: "#121212",
          weight: 2,
          dashArray: hover ? "4 4" : null,
        }).addTo(map);
      } else {
        preview.setLatLngs(path);
        preview.setStyle({ dashArray: hover ? "4 4" : null });
      }
    }

    function onClick(event) {
      points.push(event.latlng);
      dots.addLayer(
        L.circleMarker(event.latlng, {
          radius: 4,
          color: "#121212",
          fillColor: "#ffffff",
          fillOpacity: 1,
          weight: 2,
        })
      );
      redraw();
      say(
        points.length === 1
          ? "Click the next point. Double-click or press Escape to finish."
          : fmtDistance(total())
      );
    }

    function onMove(event) {
      if (!points.length) return;
      redraw(event.latlng);
      say(fmtDistance(total(event.latlng)));
    }

    function finish() {
      if (points.length > 1) {
        line = L.polyline(points, { color: "#121212", weight: 2.5 }).addTo(map);
        say(fmtDistance(total()) + " — click Measure again to clear.");
      }
      stop(true);
    }

    function onKey(event) {
      if (event.key === "Escape") finish();
    }

    function start() {
      active = true;
      points = [];
      dots.addTo(map);
      map.getContainer().classList.add("map--measuring");
      map.on("click", onClick);
      map.on("mousemove", onMove);
      map.on("dblclick", finish);
      map.doubleClickZoom.disable();
      document.addEventListener("keydown", onKey);
      say("Click a starting point.");
    }

    function stop(keepLine) {
      active = false;
      map.getContainer().classList.remove("map--measuring");
      map.off("click", onClick);
      map.off("mousemove", onMove);
      map.off("dblclick", finish);
      map.doubleClickZoom.enable();
      document.removeEventListener("keydown", onKey);

      if (preview) {
        map.removeLayer(preview);
        preview = null;
      }
      if (!keepLine) {
        map.removeLayer(dots);
        dots.clearLayers();
        if (line) {
          map.removeLayer(line);
          line = null;
        }
        say("");
      }
    }

    function clear() {
      stop(false);
      map.removeLayer(dots);
      dots.clearLayers();
      if (line) {
        map.removeLayer(line);
        line = null;
      }
      say("");
    }

    return {
      toggle: function () {
        if (active) {
          clear();
          return false;
        }
        if (line) {
          clear();
          return false;
        }
        start();
        return true;
      },
      isActive: function () {
        return active;
      },
      clear: clear,
    };
  }

  /* ---- Radius rings ------------------------------------------------------
     Drop a point, draw quarter/half/one/two mile rings, and report what falls
     inside each. The two-mile ring is the same radius the watchlist uses, so
     the two features answer the same question the same way. */

  var RINGS = [0.25, 0.5, 1, 2];

  function radiusTool(map, options) {
    options = options || {};
    var group = L.layerGroup();
    var active = false;
    var centre = null;

    function draw(latlng) {
      group.clearLayers();
      centre = latlng;

      RINGS.slice()
        .reverse()
        .forEach(function (miles) {
          var metres = miles * M_PER_MILE;
          group.addLayer(
            L.circle(latlng, {
              radius: metres,
              color: "#1c4f8f",
              weight: 1.5,
              opacity: 0.8,
              fillColor: "#1c4f8f",
              fillOpacity: 0.05,
            })
          );
          // Label on the north edge of each ring, where it is least likely to
          // sit on top of a marker cluster.
          var north = L.latLng(latlng.lat + metres / 111320, latlng.lng);
          group.addLayer(
            L.marker(north, {
              interactive: false,
              keyboard: false,
              icon: L.divIcon({
                className: "ring-label",
                html: "<span>" + (miles < 1 ? miles + " mi" : miles + " mi") + "</span>",
                iconSize: [0, 0],
              }),
            })
          );
        });

      group.addLayer(
        L.circleMarker(latlng, {
          radius: 5,
          color: "#1c4f8f",
          fillColor: "#ffffff",
          fillOpacity: 1,
          weight: 2,
        })
      );

      group.addTo(map);
      if (typeof options.onDrop === "function") {
        options.onDrop(latlng, RINGS.map(function (m) { return m * M_PER_MILE; }));
      }
    }

    function onClick(event) {
      draw(event.latlng);
      stop();
    }

    function start() {
      active = true;
      map.getContainer().classList.add("map--measuring");
      map.on("click", onClick);
      if (typeof options.onArm === "function") options.onArm();
    }

    function stop() {
      active = false;
      map.getContainer().classList.remove("map--measuring");
      map.off("click", onClick);
    }

    function clear() {
      stop();
      group.clearLayers();
      map.removeLayer(group);
      centre = null;
      if (typeof options.onClear === "function") options.onClear();
    }

    return {
      toggle: function () {
        if (active) {
          stop();
          return false;
        }
        if (centre) {
          clear();
          return false;
        }
        start();
        return true;
      },
      at: draw,
      clear: clear,
      centre: function () {
        return centre;
      },
      rings: RINGS,
    };
  }

  /* ---- Locate ------------------------------------------------------------
     Geolocation is a permission prompt, so it only ever runs on a click. The
     accuracy circle matters: a 2 km fix drawn as a precise dot is a lie the
     browser tells and the map shouldn't repeat. */

  function locate(map, onResult) {
    if (!navigator.geolocation) {
      if (onResult) onResult(new Error("This browser has no location support"));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      function (position) {
        var latlng = L.latLng(position.coords.latitude, position.coords.longitude);
        var accuracy = position.coords.accuracy || 0;

        if (!map.getBounds().pad(2).contains(latlng)) {
          if (onResult) onResult(new Error("You appear to be outside Loudoun County"));
          return;
        }

        var marker = L.circleMarker(latlng, {
          radius: 6,
          color: "#121212",
          fillColor: "#4c9a5c",
          fillOpacity: 1,
          weight: 2,
        }).addTo(map);
        if (accuracy > 50) {
          L.circle(latlng, {
            radius: accuracy,
            color: "#4c9a5c",
            weight: 1,
            fillOpacity: 0.08,
          }).addTo(map);
        }
        map.setView(latlng, 14);
        marker.bindPopup("You are about here (±" + Math.round(accuracy) + " m)").openPopup();
        if (onResult) onResult(null, latlng);
      },
      function (error) {
        if (onResult) {
          onResult(
            new Error(
              error.code === 1
                ? "Location permission was declined"
                : "Could not get your location"
            )
          );
        }
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 }
    );
  }

  /* ---- Fullscreen --------------------------------------------------------
     Safari on iOS has no Element.requestFullscreen at all, so fall back to a
     CSS class that fills the viewport. The map must be told to re-measure
     either way or it renders tiles for the old size. */

  function toggleFullscreen(map) {
    var element = map.getContainer().closest(".map-shell") || map.getContainer();

    function settled() {
      setTimeout(function () {
        map.invalidateSize();
      }, 120);
    }

    if (element.requestFullscreen && !document.fullscreenElement) {
      element.requestFullscreen().then(settled, function () {
        element.classList.add("is-pseudo-fullscreen");
        settled();
      });
      return true;
    }
    if (document.fullscreenElement) {
      document.exitFullscreen();
      settled();
      return false;
    }

    var on = element.classList.toggle("is-pseudo-fullscreen");
    settled();
    return on;
  }

  /* ---- Address search ----------------------------------------------------
     Nominatim's usage policy requires a descriptive User-Agent (a browser
     can't set one, so the Referer serves), no more than one request a second,
     and no bulk use. We only ever call it on an explicit button press, and the
     interval guard below is what keeps one impatient visitor from getting the
     whole site blocked. */

  var lastGeocode = 0;

  function geocode(query) {
    var settings = config();
    var wait = Math.max(
      0,
      (settings.GEOCODE_MIN_INTERVAL_MS || 1100) - (Date.now() - lastGeocode)
    );

    return new Promise(function (resolve) {
      setTimeout(resolve, wait);
    }).then(function () {
      lastGeocode = Date.now();
      var bounds = settings.MAP_BOUNDS || [[38.8, -78.05], [39.35, -77.2]];
      var url =
        (settings.GEOCODE_URL || "https://nominatim.openstreetmap.org/search") +
        "?format=json&limit=5&countrycodes=us&addressdetails=1" +
        "&viewbox=" +
        [bounds[0][1], bounds[1][0], bounds[1][1], bounds[0][0]].join(",") +
        "&bounded=1&q=" +
        encodeURIComponent(query);

      return fetch(url, { headers: { Accept: "application/json" } })
        .then(function (response) {
          if (!response.ok) throw new Error("Address lookup is unavailable");
          return response.json();
        })
        .then(function (results) {
          return (results || []).map(function (row) {
            return {
              label: row.display_name,
              lat: Number(row.lat),
              lng: Number(row.lon),
            };
          });
        });
    });
  }

  LDCW.mapTools = {
    measureTool: measureTool,
    radiusTool: radiusTool,
    locate: locate,
    toggleFullscreen: toggleFullscreen,
    geocode: geocode,
    fmtDistance: fmtDistance,
    M_PER_MILE: M_PER_MILE,
  };
})(window.LDCW);
