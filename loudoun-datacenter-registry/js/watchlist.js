/*
 * The watchlist and the ticker.
 *
 * A location goes on the watchlist when five or more approved reports from
 * five or more distinct households fall within two miles of it. Both halves of
 * that rule are load-bearing:
 *
 *   * Only approved reports count. If pending ones did, anyone could
 *     manufacture a public flag against a named company by filling in the form
 *     five times. Moderation is what stands between this ticker and a
 *     defamation claim.
 *
 *   * Distinct households, not distinct reports. Same reason, one step
 *     subtler: five reports from one angry neighbour is one neighbour.
 *
 * Two miles is also chosen rather than inherited. Published pins are offset
 * 100-200 m from the real address; a two-mile radius is 3,219 m, sixteen to
 * thirty-two times the jitter, so clustering the published coordinates gives
 * the same answer as clustering real ones and never needs a real one. Shrink
 * the radius below about half a mile and that stops being true — you would be
 * trading residents' privacy for map precision.
 *
 * Where the arithmetic runs depends on the backend. In demo mode every record
 * is in this browser, so it runs here. Against Supabase it cannot: anon holds
 * no read on the base table, so refresh_watchlist() does it in the database and
 * this file reads the aggregate. Same rule, same numbers, two places — see
 * sql/05_parttwo.sql.
 *
 * Wording matters as much as arithmetic. A watchlist entry is a statement about
 * *reports*, never about a company. Every string in this file says "residents
 * have reported", never "this facility is causing". Nothing here is generated.
 */

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var schema = LDCW.schema;
  var escape = schema.escapeHtml;

  function config() {
    return window.LDCW_CONFIG || {};
  }

  function radiusM() {
    return config().WATCHLIST_RADIUS_M || 3219;
  }

  function metresBetween(a, b) {
    var R = 6371008.8;
    var dLat = ((b.lat - a.lat) * Math.PI) / 180;
    var dLng = ((b.lng - a.lng) * Math.PI) / 180;
    var lat1 = (a.lat * Math.PI) / 180;
    var lat2 = (b.lat * Math.PI) / 180;
    var h =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
    return 2 * R * Math.asin(Math.sqrt(h));
  }

  /* ---- The rule ----------------------------------------------------------
     Deliberately the same shape as refresh_watchlist() in sql/05_parttwo.sql.
     If you change one, change the other, or demo mode and production will
     disagree about what counts as a cluster.

     Candidate centres are the reports themselves rather than a fixed grid:
     every real cluster contains at least one report at its core, so scanning
     reports finds the same clusters without inventing centres in empty fields.
     Candidates are then taken strongest-first, and any candidate within one
     radius of an accepted centre is dropped — otherwise a single cluster of
     eight reports produces eight nearly identical entries. */

  function compute(rows, facilities) {
    var settings = config();
    var radius = radiusM();
    var minReports = settings.WATCHLIST_MIN_REPORTS || 5;
    var minHouseholds = settings.WATCHLIST_MIN_HOUSEHOLDS || 5;

    var usable = (rows || []).filter(function (row) {
      return isFinite(row.lat) && isFinite(row.lng);
    });

    var candidates = usable
      .map(function (anchor) {
        var near = usable.filter(function (other) {
          return metresBetween(anchor, other) <= radius;
        });

        var households = {};
        near.forEach(function (row) {
          if (row.has_contact === false) return;
          households[row.household_key || row.id] = true;
        });

        var categories = {};
        var districts = {};
        var severities = [];
        var dates = [];
        near.forEach(function (row) {
          (row.categories || []).forEach(function (key) {
            categories[key] = (categories[key] || 0) + 1;
          });
          if (row.locality) districts[row.locality] = (districts[row.locality] || 0) + 1;
          severities.push(Number(row.severity) || 0);
          dates.push(new Date(row.created_at).getTime());
        });

        // Name the cluster by where most of its reports are, not by whichever
        // report happened to be the anchor. Two miles is wide enough to cross a
        // district line, and attributing nine reports to the wrong supervisor's
        // district would be a real error, not a cosmetic one.
        var byCount = Object.keys(districts).sort(function (a, b) {
          return districts[b] - districts[a] || a.localeCompare(b);
        });

        return {
          anchor_id: anchor.id,
          lat: anchor.lat,
          lng: anchor.lng,
          locality: byCount[0] || anchor.locality,
          districts: byCount,
          report_count: near.length,
          household_count: Object.keys(households).length,
          // Most-reported issue first — it is what the ticker shows.
          categories: Object.keys(categories).sort(function (a, b) {
            return categories[b] - categories[a];
          }),
          top_severity: severities.length ? Math.max.apply(null, severities) : null,
          first_report_at: dates.length ? new Date(Math.min.apply(null, dates)).toISOString() : null,
          latest_report_at: dates.length ? new Date(Math.max.apply(null, dates)).toISOString() : null,
          report_ids: near.map(function (row) {
            return row.id;
          }),
        };
      })
      .filter(function (candidate) {
        return (
          candidate.report_count >= minReports && candidate.household_count >= minHouseholds
        );
      })
      .sort(function (a, b) {
        return (
          b.report_count - a.report_count ||
          new Date(b.latest_report_at) - new Date(a.latest_report_at) ||
          String(a.anchor_id).localeCompare(String(b.anchor_id))
        );
      });

    var accepted = [];
    candidates.forEach(function (candidate) {
      var duplicate = accepted.some(function (taken) {
        return metresBetween(candidate, taken) <= radius;
      });
      if (duplicate) return;

      var nearest = null;
      var nearestDistance = Infinity;
      (facilities || []).forEach(function (facility) {
        if (!isFinite(facility.lat) || !isFinite(facility.lng)) return;
        var distance = metresBetween(candidate, facility);
        if (distance <= radius && distance < nearestDistance) {
          nearestDistance = distance;
          nearest = facility;
        }
      });

      accepted.push(
        Object.assign({}, candidate, {
          id: "wl-" + candidate.anchor_id,
          kind: nearest ? "facility" : "area",
          label: nearest
            ? nearest.name || "Data center parcel"
            : "Near " + (candidate.locality || "Loudoun County"),
          facility_id: nearest ? nearest.id : null,
          radius_m: radius,
        })
      );
    });

    return accepted;
  }

  /* ---- Loading ------------------------------------------------------------ */

  var cache = null;

  function load() {
    if (cache) return cache;

    cache = Store.watchlistSource()
      .then(function (rows) {
        // null means "a real backend computed this already" — read the table.
        if (rows === null) return Store.listWatchlist().then(function (entries) {
          return entries || [];
        });
        return Store.loadFacilities()
          .catch(function () {
            return [];
          })
          .then(function (facilities) {
            return compute(rows, facilities);
          });
      })
      .catch(function () {
        // A watchlist that fails to load must never take a page down with it.
        // It is a supplementary view over data shown elsewhere anyway.
        return [];
      });

    return cache;
  }

  /* ---- Copy ---------------------------------------------------------------
     One place, so the ticker, the list and the detail page cannot end up
     describing the same number three different ways. */

  /* A two-mile circle regularly crosses a district line, and saying "Broad Run"
     when four of the nine reports are in Ashburn would send a reader to the
     wrong supervisor. Name every district the cluster actually touches. */
  function districtLabel(entry) {
    var list = entry.districts && entry.districts.length ? entry.districts : [entry.locality];
    list = list.filter(Boolean);
    if (!list.length) return "Loudoun County";
    if (list.length === 1) return list[0];
    if (list.length === 2) return list[0] + " and " + list[1];
    return list.slice(0, -1).join(", ") + " and " + list[list.length - 1];
  }

  function headline(entry) {
    return (
      schema.formatNumber(entry.report_count) +
      " report" +
      (entry.report_count === 1 ? "" : "s") +
      " within 2 miles"
    );
  }

  function summary(entry) {
    return (
      schema.formatNumber(entry.household_count) +
      " household" +
      (entry.household_count === 1 ? "" : "s") +
      " have reported " +
      (entry.categories || [])
        .slice(0, 3)
        .map(function (key) {
          return schema.categoryLabel(key).toLowerCase();
        })
        .join(", ") +
      " within 2 miles of here"
    );
  }

  var DISCLAIMER =
    "Watchlist entries reflect the number and proximity of resident reports. " +
    "They are not findings of fact and do not establish that any facility caused any condition.";

  /* ---- The ticker ---------------------------------------------------------
     Not a <marquee>. That element is deprecated, cannot be paused, and screen
     readers handle it badly. This is a CSS transform on a duplicated track,
     inside a labelled region, with a real pause control, and it does not move
     at all under prefers-reduced-motion — where it becomes a plain
     horizontally scrollable strip instead. */

  var DISMISS_KEY = "ldcw.watchlist.dismissed";

  function highestSeen(entries) {
    return entries
      .map(function (entry) {
        return String(entry.id);
      })
      .sort()
      .join("|");
  }

  function wasDismissed(entries) {
    try {
      return sessionStorage.getItem(DISMISS_KEY) === highestSeen(entries);
    } catch (err) {
      return false;
    }
  }

  function remember(entries) {
    try {
      sessionStorage.setItem(DISMISS_KEY, highestSeen(entries));
    } catch (err) {
      /* Storage blocked. The ticker comes back next page view; that's fine. */
    }
  }

  function tickerItem(entry) {
    return (
      '<a class="ticker__item" href="watchlist.html?id=' +
      encodeURIComponent(entry.id) +
      '">' +
      '<span class="ticker__flag" aria-hidden="true"></span>' +
      '<span class="ticker__place">' +
      escape(entry.label) +
      "</span>" +
      '<span class="ticker__count">' +
      escape(headline(entry)) +
      "</span>" +
      ((entry.categories || []).length
        ? '<span class="ticker__cats">' +
          escape(
            entry.categories
              .slice(0, 2)
              .map(function (key) {
                return schema.categoryLabel(key).toLowerCase();
              })
              .join(", ")
          ) +
          "</span>"
        : "") +
      "</a>"
    );
  }

  function mountTicker() {
    var host = document.getElementById("watch-ticker");
    if (!host) return;

    load().then(function (entries) {
      // An empty watchlist means no bar at all. A placeholder that says
      // "nothing yet" is a permanent strip of nothing across every page.
      if (!entries.length) return;
      if (wasDismissed(entries)) return;

      var top = entries.slice(0, config().WATCHLIST_TICKER_MAX || 10);
      var items = top.map(tickerItem).join("");

      host.className = "ticker";
      host.setAttribute("aria-label", "Community report watchlist");
      host.innerHTML =
        '<div class="ticker__lead"><a href="watchlist.html">Watchlist</a></div>' +
        '<div class="ticker__viewport">' +
        '<div class="ticker__track">' +
        // The track is duplicated so the animation can translate a full copy
        // width and restart with no visible seam. The clone is hidden from
        // assistive technology, which would otherwise read every entry twice.
        '<div class="ticker__run">' +
        items +
        "</div>" +
        '<div class="ticker__run" aria-hidden="true">' +
        items +
        "</div>" +
        "</div></div>" +
        '<div class="ticker__controls">' +
        '<button type="button" class="ticker__btn" data-ticker-pause aria-pressed="false">' +
        "Pause</button>" +
        '<button type="button" class="ticker__btn" data-ticker-dismiss ' +
        'aria-label="Hide the watchlist ticker">&times;</button>' +
        "</div>";
      host.hidden = false;

      var track = host.querySelector(".ticker__track");
      // Duration scaled to content, so two entries don't crawl and ten don't
      // blur past. ~55 px/sec reads comfortably.
      var width = host.querySelector(".ticker__run").scrollWidth;
      track.style.setProperty("--ticker-duration", Math.max(18, Math.round(width / 55)) + "s");

      var pause = host.querySelector("[data-ticker-pause]");
      pause.addEventListener("click", function () {
        var paused = host.classList.toggle("is-paused");
        pause.setAttribute("aria-pressed", String(paused));
        pause.textContent = paused ? "Play" : "Pause";
      });

      host.querySelector("[data-ticker-dismiss]").addEventListener("click", function () {
        remember(entries);
        host.hidden = true;
      });
    });
  }

  /* ---- The page ----------------------------------------------------------- */

  function entryCard(entry) {
    return (
      '<article class="watch-card">' +
      '<div class="watch-card__rank">' +
      '<span class="watch-card__count">' +
      schema.formatNumber(entry.report_count) +
      "</span>" +
      '<span class="watch-card__unit">report' +
      (entry.report_count === 1 ? "" : "s") +
      "</span></div>" +
      '<div class="watch-card__body">' +
      '<h3><a href="watchlist.html?id=' +
      encodeURIComponent(entry.id) +
      '">' +
      escape(entry.label) +
      "</a></h3>" +
      '<p class="watch-card__meta">' +
      escape(districtLabel(entry)) +
      " · " +
      escape(String(entry.household_count)) +
      " household" +
      (entry.household_count === 1 ? "" : "s") +
      (entry.latest_report_at
        ? " · most recent " + escape(schema.formatRelative(entry.latest_report_at))
        : "") +
      "</p>" +
      '<div class="badge-list">' +
      (entry.categories || [])
        .slice(0, 4)
        .map(function (key) {
          return (
            '<span class="badge badge--neutral">' + escape(schema.categoryLabel(key)) + "</span>"
          );
        })
        .join("") +
      "</div>" +
      "</div>" +
      "</article>"
    );
  }

  /* The list and the detail view each render their own page header. The
     alternative — a static header in the HTML plus a results div — meant the
     detail view had to reach out and rewrite a heading that belonged to
     someone else. */
  var LIST_HEADER =
    '<div class="page-header">' +
    '<p class="kicker">Where reports cluster</p>' +
    "<h1>Watchlist</h1>" +
    '<p class="lead">Locations where enough separate households have reported problems close ' +
    "together that the cluster is worth flagging. Every entry is a statement about reports, " +
    "not about any company.</p>" +
    "</div>";

  function renderList(host, entries) {
    if (!entries.length) {
      host.innerHTML =
        LIST_HEADER +
        '<div class="empty-state">' +
        '<p class="empty-state__title">Nothing on the watchlist right now</p>' +
        "<p>A location appears here once " +
        (config().WATCHLIST_MIN_REPORTS || 5) +
        " or more approved reports from " +
        (config().WATCHLIST_MIN_HOUSEHOLDS || 5) +
        " or more separate households fall within two miles of it. " +
        "That threshold is deliberately hard to reach by accident.</p>" +
        '<p><a class="btn btn--primary" href="report.html">Report an issue</a></p>' +
        "</div>";
      return;
    }

    host.innerHTML =
      LIST_HEADER +
      '<p class="muted">' +
      schema.formatNumber(entries.length) +
      (entries.length === 1
        ? " location currently meets the threshold."
        : " locations currently meet the threshold, ordered by the number of reports nearby.") +
      "</p>" +
      '<div class="watch-list">' +
      entries.map(entryCard).join("") +
      "</div>";
  }

  function renderDetail(host, entry, reports) {
    var inCluster = (reports || []).filter(function (report) {
      return (entry.report_ids || []).indexOf(report.id) !== -1;
    });

    // A Supabase-backed watchlist row carries no report_ids — the database
    // returns counts, not membership. Fall back to a live proximity test.
    if (!inCluster.length && isFinite(entry.lat)) {
      inCluster = (reports || []).filter(function (report) {
        return (
          isFinite(report.lat) && metresBetween(entry, report) <= (entry.radius_m || radiusM())
        );
      });
    }

    var categoryRows = (entry.categories || [])
      .map(function (key) {
        var count = inCluster.filter(function (report) {
          return (report.categories || []).indexOf(key) !== -1;
        }).length;
        return (
          "<tr><th>" +
          escape(schema.categoryLabel(key)) +
          "</th><td>" +
          schema.formatNumber(count) +
          "</td></tr>"
        );
      })
      .join("");

    host.innerHTML =
      '<p class="breadcrumb"><a href="watchlist.html">&larr; All watchlist locations</a></p>' +
      '<div class="page-header">' +
      '<p class="kicker">Watchlist</p>' +
      "<h1>" +
      escape(entry.label) +
      "</h1>" +
      '<p class="lead">' +
      escape(
        districtLabel(entry) +
          " — " +
          schema.formatNumber(entry.report_count) +
          " approved report" +
          (entry.report_count === 1 ? "" : "s") +
          " from " +
          schema.formatNumber(entry.household_count) +
          " separate household" +
          (entry.household_count === 1 ? "" : "s") +
          " fall within two miles of this location."
      ) +
      "</p>" +
      "</div>" +
      '<div class="callout callout--muted"><strong>What this does and does not say.</strong> ' +
      escape(DISCLAIMER) +
      "</div>" +
      '<div class="stat-grid stat-grid--4">' +
      statTile(schema.formatNumber(entry.report_count), "Reports within 2 miles") +
      statTile(schema.formatNumber(entry.household_count), "Separate households") +
      statTile(
        entry.top_severity ? entry.top_severity + "/5" : "—",
        "Highest impact reported"
      ) +
      statTile(
        entry.latest_report_at ? schema.formatRelative(entry.latest_report_at) : "—",
        "Most recent report"
      ) +
      "</div>" +
      '<section class="section"><h2 class="section__title">Where</h2>' +
      '<div class="map-shell"><div class="map map--compact" id="watch-map"></div></div>' +
      '<p class="tiny muted">The circle is the two-mile radius the rule uses. Individual pins ' +
      "are offset 100–200 metres from the addresses given.</p></section>" +
      (categoryRows
        ? '<section class="section"><h2 class="section__title">What is being reported</h2>' +
          '<table class="table"><thead><tr><th>Issue</th><th>Reports</th></tr></thead>' +
          "<tbody>" +
          categoryRows +
          "</tbody></table></section>"
        : "") +
      '<section class="section"><h2 class="section__title">The reports</h2>' +
      '<div id="watch-reports"></div></section>' +
      '<section class="section"><h2 class="section__title">Who represents this area</h2>' +
      "<p>" +
      escape(districtLabel(entry)) +
      (entry.districts && entry.districts.length > 1
        ? " — this cluster crosses a district line, so more than one supervisor covers it. Each"
        : " is represented on the Board of Supervisors by its district supervisor. Your supervisor") +
      " can be reached through the county. " +
      'See <a href="resources.html#official">Resources</a> for how to raise this with the ' +
      "county, and the numbers to call while something is actually happening.</p></section>";

    LDCW.ui.renderReportList(document.getElementById("watch-reports"), inCluster, {
      emptyTitle: "No individual reports to show",
      emptyBody:
        "The counts above come from the database. Individual reports appear here once they load.",
    });

    if (LDCW.map && isFinite(entry.lat)) {
      var controller = LDCW.map.createMap("watch-map", {
        scrollWheelZoom: false,
        ariaLabel: "Map of the reports clustered near " + entry.label,
      });
      if (controller) {
        controller.setReports(inCluster);
        Store.loadFacilities().then(function (facilities) {
          controller.setFacilities(facilities);
        });
        L.circle([entry.lat, entry.lng], {
          radius: entry.radius_m || radiusM(),
          color: "#b3261e",
          weight: 1.5,
          fillColor: "#b3261e",
          fillOpacity: 0.06,
        }).addTo(controller.map);
        controller.focus(entry.lat, entry.lng, 12);
      }
    }
  }

  function statTile(value, label) {
    return (
      '<div class="stat"><span class="stat__value">' +
      escape(String(value)) +
      '</span><span class="stat__label">' +
      escape(label) +
      "</span></div>"
    );
  }

  function mountPage() {
    var host = document.getElementById("watchlist-body");
    if (!host) return;

    var id = new URLSearchParams(window.location.search).get("id");
    LDCW.ui.showLoading(host, "Working out which locations meet the threshold…");

    Promise.all([load(), Store.listApproved({}).catch(function () { return []; })]).then(
      function (results) {
        var entries = results[0];
        var reports = results[1];

        if (!id) {
          renderList(host, entries);
          return;
        }

        var entry = entries.filter(function (candidate) {
          return String(candidate.id) === id;
        })[0];

        if (!entry) {
          host.innerHTML =
            '<p class="breadcrumb"><a href="watchlist.html">&larr; All watchlist locations</a></p>' +
            '<div class="empty-state"><p class="empty-state__title">This location is no longer ' +
            "on the watchlist</p><p>Entries are recalculated as reports are approved, so a " +
            "location can drop off. The list is up to date.</p></div>";
          return;
        }

        renderDetail(host, entry, reports);
        document.title = entry.label + " — Watchlist — Loudoun Data Center Watch";
      }
    );
  }

  LDCW.watchlist = {
    compute: compute,
    load: load,
    mountTicker: mountTicker,
    mountPage: mountPage,
    headline: headline,
    summary: summary,
    DISCLAIMER: DISCLAIMER,
  };

  function boot() {
    mountTicker();
    mountPage();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})(window.LDCW);
