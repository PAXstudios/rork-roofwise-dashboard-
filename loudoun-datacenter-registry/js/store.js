/*
 * The single data entry point for every page.
 *
 * Picks a backend at load time — Supabase if js/config.js has credentials,
 * otherwise the localStorage demo — and exposes one interface over both. It
 * also loads the county facility layers and derives the statistics, so those
 * live in one place rather than being recomputed per page.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var config = window.LDCW_CONFIG || {};
  var hasSupabase = Boolean(config.SUPABASE_URL && config.SUPABASE_ANON_KEY);
  var backend = hasSupabase ? LDCW.SupabaseStore : LDCW.LocalStore;

  if (!backend) {
    throw new Error(
      "No storage backend loaded. Include local-store.js and supabase-store.js before store.js."
    );
  }

  /* ---- Facility data -----------------------------------------------------
     Static GeoJSON produced by scripts/refresh-facilities.py. Fetched once and
     cached for the lifetime of the page. */

  var facilityCache = null;
  var summaryCache = null;

  function loadJson(path) {
    return fetch(path, { cache: "default" }).then(function (response) {
      if (!response.ok) {
        throw new Error("Couldn't load " + path + " (" + response.status + ").");
      }
      return response.json();
    });
  }

  function loadFacilities() {
    if (facilityCache) return Promise.resolve(facilityCache);

    return loadJson("data/facilities.geojson").then(function (geojson) {
      facilityCache = (geojson.features || []).map(function (feature) {
        var coordinates = (feature.geometry && feature.geometry.coordinates) || [];
        return Object.assign({}, feature.properties, {
          lng: coordinates[0],
          lat: coordinates[1],
        });
      });
      return facilityCache;
    });
  }

  function loadSummary() {
    if (summaryCache) return Promise.resolve(summaryCache);
    return loadJson("data/summary.json").then(function (data) {
      summaryCache = data;
      return data;
    });
  }

  /* ---- Statistics --------------------------------------------------------
     Derived on the client from the approved reports the visitor can already
     see, so the numbers on the statistics page always match the map. */

  function countBy(rows, pick) {
    var totals = {};
    rows.forEach(function (row) {
      var values = pick(row);
      (Array.isArray(values) ? values : [values]).forEach(function (value) {
        if (value == null || value === "") return;
        totals[value] = (totals[value] || 0) + 1;
      });
    });
    return totals;
  }

  function rank(totals, total) {
    return Object.keys(totals)
      .map(function (key) {
        return {
          key: key,
          count: totals[key],
          share: total ? totals[key] / total : 0,
        };
      })
      .sort(function (a, b) {
        return b.count - a.count || a.key.localeCompare(b.key);
      });
  }

  function monthlyCounts(rows, months) {
    var buckets = [];
    var now = new Date();
    var index;

    for (index = months - 1; index >= 0; index--) {
      var date = new Date(now.getFullYear(), now.getMonth() - index, 1);
      buckets.push({
        key: date.toISOString().slice(0, 7),
        label: date.toLocaleDateString("en-US", { month: "short" }),
        year: date.getFullYear(),
        count: 0,
      });
    }

    var byKey = {};
    buckets.forEach(function (bucket) {
      byKey[bucket.key] = bucket;
    });

    rows.forEach(function (row) {
      var key = String(row.created_at || "").slice(0, 7);
      if (byKey[key]) byKey[key].count += 1;
    });

    return buckets;
  }

  function computeStats(rows, summary) {
    var total = rows.length;
    var dayMs = 86400000;
    var since30 = Date.now() - 30 * dayMs;

    var recent = rows.filter(function (row) {
      return new Date(row.created_at).getTime() >= since30;
    });

    var zips = {};
    rows.forEach(function (row) {
      if (row.zip) zips[row.zip] = true;
    });

    var localities = {};
    rows.forEach(function (row) {
      if (row.locality) localities[row.locality] = true;
    });

    var severityTotals = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
    var severitySum = 0;
    rows.forEach(function (row) {
      var value = Number(row.severity);
      if (severityTotals[value] != null) {
        severityTotals[value] += 1;
        severitySum += value;
      }
    });

    return {
      total: total,
      localityCount: Object.keys(localities).length,
      zipCount: Object.keys(zips).length,
      last30Days: recent.length,
      averageSeverity: total ? severitySum / total : 0,

      byCategory: rank(
        countBy(rows, function (row) {
          return row.categories || [];
        }),
        total
      ),
      byLocality: rank(
        countBy(rows, function (row) {
          return row.locality;
        }),
        total
      ),
      byZip: rank(
        countBy(rows, function (row) {
          return row.zip;
        }),
        total
      ),
      byFacilityStatus: rank(
        countBy(rows, function (row) {
          return row.facility_status;
        }),
        total
      ),
      bySeverity: [1, 2, 3, 4, 5].map(function (level) {
        return {
          key: String(level),
          count: severityTotals[level],
          share: total ? severityTotals[level] / total : 0,
        };
      }),
      byMonth: monthlyCounts(rows, 12),

      // County context, so citizen reports sit next to the official scale.
      facilities: summary || null,
    };
  }

  /* ---- Public interface --------------------------------------------------- */

  var Store = {
    mode: backend.mode,
    isDemo: backend.isDemo === true,

    listApproved: function (filter) {
      return backend.listApproved(filter);
    },

    getReport: function (id) {
      return backend.getReport(id);
    },

    /* Raw-ish rows carrying a household key, for computing the watchlist in
       the browser. Resolves to null against a real backend, where the
       computation belongs in the database. */
    watchlistSource: function () {
      return backend.watchlistSource
        ? backend.watchlistSource()
        : Promise.resolve(null);
    },

    /* Pre-computed watchlist rows. Only the Supabase backend has these. */
    listWatchlist: function () {
      return backend.listWatchlist ? backend.listWatchlist() : Promise.resolve(null);
    },

    submitReport: function (draft, files) {
      return backend.submitReport(draft, files);
    },

    signIn: function (email, password) {
      return backend.signIn(email, password);
    },

    signOut: function () {
      return backend.signOut();
    },

    currentUser: function () {
      return backend.currentUser();
    },

    isAdmin: function () {
      return backend.isAdmin ? backend.isAdmin() : Promise.resolve(false);
    },

    listPending: function (options) {
      return backend.listPending(options);
    },

    moderate: function (id, status, note) {
      return backend.moderate(id, status, note);
    },

    loadFacilities: loadFacilities,
    loadSummary: loadSummary,
    loadJson: loadJson,

    stats: function (filter) {
      return Promise.all([backend.listApproved(filter), loadSummary().catch(function () {
        return null;
      })]).then(function (results) {
        return computeStats(results[0], results[1]);
      });
    },

    /* Exposed for the statistics page's CSV export and for tests. */
    computeStats: computeStats,

    reset: function () {
      return backend.reset ? backend.reset() : Promise.resolve();
    },
  };

  LDCW.Store = Store;

  /* ---- Demo-mode banner ---------------------------------------------------
     Every page includes an empty .demo-banner; it only becomes visible when no
     Supabase project is configured. Visitors should never be unsure whether
     what they're reading is real. */

  function showDemoBanner() {
    if (!Store.isDemo) return;
    var banner = document.querySelector(".demo-banner");
    if (!banner) return;

    banner.innerHTML =
      '<div class="container"><strong>Demo mode.</strong> ' +
      "The reports shown here are illustrative samples, not real submissions, and anything you submit is saved only in this browser. " +
      '<a href="about.html#demo-mode">How to connect a live database</a>.</div>';
    banner.hidden = false;
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", showDemoBanner);
  } else {
    showDemoBanner();
  }
})(window.LDCW);
