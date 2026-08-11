/*
 * Basemaps and data overlays.
 *
 * Split out of map.js so that file stays about markers and filtering. Nothing
 * here knows about reports or facilities as records — it deals in tiles and
 * geometry.
 *
 * Three things worth knowing before changing anything:
 *
 *   1. The Esri and USGS tile services address tiles as {z}/{y}/{x}; OSM uses
 *      {z}/{x}/{y}. Both render without error if you get it wrong, they just
 *      render the wrong part of the world. The URLs live in config.js.
 *
 *   2. Attribution is a licence condition. Leaflet swaps it with the layer
 *      automatically, which is why each basemap carries its own string rather
 *      than the page hard-coding one.
 *
 *   3. Overlay geometry is loaded lazily, on first toggle. The parcel outlines
 *      and building footprints are ~170 KB together and most visitors never
 *      turn them on; paying for them on every page load would be the single
 *      biggest thing slowing the map down.
 */

(function (LDCW) {
  "use strict";

  function config() {
    return window.LDCW_CONFIG || {};
  }

  var STATUS_COLORS = {
    operational: "#b3261e",
    under_construction: "#b26a00",
    proposed: "#1c4f8f",
    unknown: "#616a7b",
  };

  /* ---- Basemaps --------------------------------------------------------- */

  function buildBasemaps(map) {
    var defs = config().BASEMAPS || [];
    var layers = {};
    var active = null;

    defs.forEach(function (def) {
      layers[def.key] = L.tileLayer(def.url, {
        attribution: def.attribution,
        maxZoom: def.maxZoom || 19,
        // Every one of these services covers the whole world at these zooms,
        // so a missing tile means a network problem, not a gap in coverage.
        // A blank tile reads better than Leaflet's broken-image icon.
        errorTileUrl:
          "data:image/gif;base64,R0lGODlhAQABAIAAAOfn5wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==",
      });
    });

    function select(key) {
      var def = null;
      for (var i = 0; i < defs.length; i += 1) {
        if (defs[i].key === key) def = defs[i];
      }
      if (!def || !layers[key]) return null;

      if (active && layers[active]) map.removeLayer(layers[active]);
      layers[key].addTo(map);
      // Tiles must sit under every vector overlay. Leaflet's default pane
      // ordering already does this, but an explicit bringToBack survives a
      // later reorder by someone who doesn't know that.
      layers[key].bringToBack();
      active = key;

      // Markers are drawn for a light background. On aerial imagery they need
      // a halo or they disappear over dark tree cover and asphalt.
      var container = map.getContainer();
      container.classList.toggle("map--dark-base", def.dark === true);

      return def;
    }

    return {
      defs: defs,
      select: select,
      active: function () {
        return active;
      },
    };
  }

  /* ---- Overlays --------------------------------------------------------- */

  var geoCache = {};

  function loadGeo(path) {
    if (geoCache[path]) return geoCache[path];
    geoCache[path] = fetch(path)
      .then(function (response) {
        if (!response.ok) throw new Error(path + " " + response.status);
        return response.json();
      })
      .catch(function (error) {
        // Let a later toggle retry rather than caching the failure forever.
        delete geoCache[path];
        throw error;
      });
    return geoCache[path];
  }

  function parcelLayer() {
    return loadGeo("data/facility-outlines.geojson").then(function (geojson) {
      return L.geoJSON(geojson, {
        interactive: false,
        style: function (feature) {
          var color = STATUS_COLORS[feature.properties.status] || STATUS_COLORS.unknown;
          return { color: color, weight: 1.5, opacity: 0.9, fillColor: color, fillOpacity: 0.18 };
        },
      });
    });
  }

  function buildingLayer() {
    return loadGeo("data/facility-buildings.geojson").then(function (geojson) {
      return L.geoJSON(geojson, {
        interactive: false,
        style: { color: "#121212", weight: 0.75, opacity: 0.85, fillColor: "#121212", fillOpacity: 0.5 },
      });
    });
  }

  function districtLayer() {
    return loadGeo("data/districts.geojson").then(function (geojson) {
      var group = L.geoJSON(geojson, {
        interactive: false,
        style: { color: "#3d4451", weight: 1.5, opacity: 0.75, fill: false, dashArray: "5 4" },
      });

      // Labels as their own markers rather than tooltips: tooltips are tied to
      // hover and pointer events, and these need to be permanently visible on
      // a layer that deliberately doesn't take pointer events at all.
      geojson.features.forEach(function (feature) {
        var centre = polygonCentroid(feature.geometry);
        if (!centre) return;
        group.addLayer(
          L.marker([centre[1], centre[0]], {
            interactive: false,
            keyboard: false,
            icon: L.divIcon({
              className: "district-label",
              html: '<span>' + escapeHtml(feature.properties.name) + "</span>",
              iconSize: [0, 0],
            }),
          })
        );
      });

      return group;
    });
  }

  /* Area-weighted centroid of the largest ring. The bounding-box centre of an
     L-shaped district lands outside it, which puts the label in a neighbour. */
  function polygonCentroid(geometry) {
    if (!geometry) return null;
    var polygons =
      geometry.type === "MultiPolygon" ? geometry.coordinates : [geometry.coordinates];

    var best = null;
    var bestArea = 0;

    polygons.forEach(function (rings) {
      var ring = rings && rings[0];
      if (!ring || ring.length < 4) return;

      var twiceArea = 0;
      var x = 0;
      var y = 0;
      for (var i = 0; i < ring.length - 1; i += 1) {
        var cross = ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1];
        twiceArea += cross;
        x += (ring[i][0] + ring[i + 1][0]) * cross;
        y += (ring[i][1] + ring[i + 1][1]) * cross;
      }
      if (twiceArea === 0) return;

      var area = Math.abs(twiceArea / 2);
      if (area > bestArea) {
        bestArea = area;
        best = [x / (3 * twiceArea), y / (3 * twiceArea)];
      }
    });

    return best;
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  /* ---- Heat layer --------------------------------------------------------
     A canvas overlay rather than a plugin. leaflet.heat is only ~4 KB, but it
     is another vendored dependency to keep current, and the algorithm is
     genuinely short: stamp a radial alpha gradient per point, then map the
     accumulated alpha through a colour ramp. Doing it here also lets the ramp
     use the site's own palette instead of the default rainbow, which reads as
     a weather map rather than a count of complaints. */

  var HeatLayer = L.Layer.extend({
    initialize: function (points, options) {
      this._points = points || [];
      this._radius = (options && options.radius) || 26;
      this._blur = (options && options.blur) || 16;
    },

    setPoints: function (points) {
      this._points = points || [];
      if (this._canvas) this._redraw();
      return this;
    },

    onAdd: function (map) {
      this._map = map;
      this._canvas = L.DomUtil.create("canvas", "leaflet-heat-layer leaflet-layer");
      var size = map.getSize();
      this._canvas.width = size.x;
      this._canvas.height = size.y;

      map.getPanes().overlayPane.appendChild(this._canvas);
      map.on("moveend zoomend resize", this._redraw, this);
      // Keep the canvas pinned to the pane origin during a pan, otherwise it
      // detaches from the map and slides across the viewport.
      map.on("move", this._reposition, this);
      this._reposition();
      this._redraw();
    },

    onRemove: function (map) {
      map.off("moveend zoomend resize", this._redraw, this);
      map.off("move", this._reposition, this);
      if (this._canvas && this._canvas.parentNode) {
        this._canvas.parentNode.removeChild(this._canvas);
      }
      this._canvas = null;
    },

    _reposition: function () {
      if (!this._canvas || !this._map) return;
      L.DomUtil.setPosition(this._canvas, this._map.containerPointToLayerPoint([0, 0]));
    },

    _stamp: function () {
      if (this._stampCanvas) return this._stampCanvas;
      var r = this._radius + this._blur;
      var stamp = document.createElement("canvas");
      stamp.width = stamp.height = r * 2;
      var ctx = stamp.getContext("2d");
      var gradient = ctx.createRadialGradient(r, r, 0, r, r, r);
      gradient.addColorStop(0, "rgba(0,0,0,0.85)");
      gradient.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, r * 2, r * 2);
      this._stampCanvas = stamp;
      return stamp;
    },

    _redraw: function () {
      if (!this._canvas || !this._map) return;

      var map = this._map;
      var size = map.getSize();
      if (this._canvas.width !== size.x || this._canvas.height !== size.y) {
        this._canvas.width = size.x;
        this._canvas.height = size.y;
      }
      this._reposition();

      var ctx = this._canvas.getContext("2d");
      ctx.clearRect(0, 0, size.x, size.y);
      if (!this._points.length) return;

      var stamp = this._stamp();
      var offset = this._radius + this._blur;
      var bounds = map.getBounds().pad(0.2);
      var drawn = 0;

      this._points.forEach(function (point) {
        if (!bounds.contains(point)) return;
        var p = map.latLngToContainerPoint(point);
        ctx.drawImage(stamp, p.x - offset, p.y - offset);
        drawn += 1;
      });
      if (!drawn) return;

      // Colourise: read back the accumulated alpha and map it through a ramp.
      var image = ctx.getImageData(0, 0, size.x, size.y);
      var data = image.data;
      var ramp = this._ramp();
      for (var i = 3; i < data.length; i += 4) {
        var alpha = data[i];
        if (!alpha) continue;
        var offsetIntoRamp = alpha * 4;
        data[i - 3] = ramp[offsetIntoRamp];
        data[i - 2] = ramp[offsetIntoRamp + 1];
        data[i - 1] = ramp[offsetIntoRamp + 2];
        data[i] = Math.min(255, alpha * 1.6);
      }
      ctx.putImageData(image, 0, 0);
    },

    _ramp: function () {
      if (this._rampData) return this._rampData;
      var canvas = document.createElement("canvas");
      canvas.width = 1;
      canvas.height = 256;
      var ctx = canvas.getContext("2d");
      var gradient = ctx.createLinearGradient(0, 0, 0, 256);
      gradient.addColorStop(0.0, "#1c4f8f");
      gradient.addColorStop(0.45, "#7a8bbd");
      gradient.addColorStop(0.7, "#d8a23a");
      gradient.addColorStop(0.9, "#c2571b");
      gradient.addColorStop(1.0, "#8c1d14");
      ctx.fillStyle = gradient;
      ctx.fillRect(0, 0, 1, 256);
      this._rampData = ctx.getImageData(0, 0, 1, 256).data;
      return this._rampData;
    },
  });

  /* ---- Public ----------------------------------------------------------- */

  var OVERLAY_DEFS = [
    {
      key: "parcels",
      label: "Parcel boundaries",
      hint: "The real footprint of each site, not just a pin",
      build: parcelLayer,
    },
    {
      key: "buildings",
      label: "Building outlines",
      hint: "271 data center buildings",
      build: buildingLayer,
    },
    {
      key: "districts",
      label: "Election districts",
      hint: "Who represents this ground",
      build: districtLayer,
    },
    {
      key: "heat",
      label: "Report density",
      hint: "Where community reports cluster",
      build: null, // built from live report data by map.js
    },
  ];

  LDCW.mapLayers = {
    buildBasemaps: buildBasemaps,
    OVERLAY_DEFS: OVERLAY_DEFS,
    STATUS_COLORS: STATUS_COLORS,
    heatLayer: function (points, options) {
      return new HeatLayer(points, options);
    },
    polygonCentroid: polygonCentroid,
  };
})(window.LDCW);
