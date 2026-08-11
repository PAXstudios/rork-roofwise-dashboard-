/*
 * The full record for one community report.
 *
 * Renders in two places from one function: a sheet that slides in over the map
 * or the list, and a standalone page at report-detail.html?id=… so a report can
 * be linked to, shared and previewed.
 *
 * The privacy rule does not change here. This view shows more of what the
 * reporter *wrote* — the untruncated description, the notes, every photo. It
 * shows nothing about *who they are*. There is no name, no email, no phone, no
 * street address and no exact coordinate anywhere in this file, because the
 * store never hands the browser those fields in the first place: everything
 * comes through schema.toPublicReport, which mirrors the public_reports view.
 *
 * If you add a field here, check it exists on that view before you reach for
 * it. A field that only exists on the base table will render as "undefined" in
 * demo mode and leak in production.
 */

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var schema = LDCW.schema;
  var escape = schema.escapeHtml;

  var NEARBY_RADIUS_M = 805; // half a mile

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

  function permalink(id) {
    return "report-detail.html?id=" + encodeURIComponent(id);
  }

  /* ---- Markup ------------------------------------------------------------ */

  function detailMarkup(report, context) {
    context = context || {};

    var severity = Number(report.severity) || 0;
    var where =
      escape(report.locality || "Loudoun County") + (report.zip ? " · " + escape(report.zip) : "");

    var categories = (report.categories || [])
      .map(function (key) {
        return '<span class="badge badge--neutral">' + escape(schema.categoryLabel(key)) + "</span>";
      })
      .join("");

    var photos = (report.photo_urls || [])
      .map(function (url, index) {
        return (
          '<button type="button" class="photo-grid__item" data-photo-index="' +
          index +
          '" aria-label="Open photo ' +
          (index + 1) +
          " of " +
          report.photo_urls.length +
          ' at full size">' +
          '<img src="' +
          escape(url) +
          '" alt="Photo ' +
          (index + 1) +
          " submitted with a community report in " +
          escape(report.locality || "Loudoun County") +
          '" loading="lazy" decoding="async">' +
          "</button>"
        );
      })
      .join("");

    var meta = [];
    meta.push(["Submitted", schema.formatDate(report.created_at)]);
    if (report.occurred_at) meta.push(["When it happened", schema.formatDate(report.occurred_at)]);
    meta.push(["District", report.locality || "Not given"]);
    if (report.zip) meta.push(["ZIP code", report.zip]);
    if (report.facility_name) {
      meta.push([
        "Facility named by the reporter",
        report.facility_name +
          (report.facility_status && report.facility_status !== "unknown"
            ? " (" + schema.statusLabel(report.facility_status) + ")"
            : ""),
      ]);
    }
    if (report.facility_operator) meta.push(["Recorded owner", report.facility_operator]);

    var metaRows = meta
      .map(function (pair) {
        return "<dt>" + escape(pair[0]) + "</dt><dd>" + escape(pair[1]) + "</dd>";
      })
      .join("");

    var notes = report.other_notes
      ? '<h3 class="detail__subhead">Anything else the reporter added</h3>' +
        '<p class="detail__body">' +
        escape(report.other_notes) +
        "</p>"
      : "";

    var demoNote = report.is_demo
      ? '<p class="callout callout--warning"><strong>Sample report.</strong> ' +
        "Illustrative only — not a real submission.</p>"
      : "";

    var nearby = context.nearby
      ? '<div class="detail__nearby" data-nearby></div>'
      : "";

    return (
      '<div class="detail">' +
      '<div class="detail__head">' +
      '<p class="kicker">Community report</p>' +
      "<h2>" +
      where +
      "</h2>" +
      '<p class="detail__when">' +
      escape(schema.formatRelative(report.created_at)) +
      " · " +
      escape(schema.formatDate(report.created_at)) +
      "</p>" +
      "</div>" +
      demoNote +
      '<div class="detail__badges">' +
      '<div class="badge-list">' +
      categories +
      "</div>" +
      '<span class="severity severity--' +
      severity +
      '"><span class="severity__dot" aria-hidden="true"></span>' +
      escape(String(severity)) +
      " — " +
      escape(schema.severityLabel(severity)) +
      "</span>" +
      "</div>" +
      '<h3 class="detail__subhead">What the resident described</h3>' +
      '<p class="detail__body">' +
      escape(report.description || "") +
      "</p>" +
      notes +
      (photos
        ? '<h3 class="detail__subhead">Photos submitted with this report</h3>' +
          '<div class="photo-grid">' +
          photos +
          "</div>" +
          '<p class="tiny muted">Location data was stripped from these images in the ' +
          "browser before upload.</p>"
        : "") +
      '<h3 class="detail__subhead">Record</h3>' +
      '<dl class="detail__meta">' +
      metaRows +
      "</dl>" +
      nearby +
      '<p class="callout callout--muted"><strong>The location shown on the map is ' +
      "approximate.</strong> Every published pin is offset 100–200 metres from the address " +
      "given, so a report can be placed in a neighbourhood without identifying a household. " +
      "This is an unverified first-hand account, not a finding of fact.</p>" +
      '<div class="detail__actions">' +
      '<a class="btn btn--primary btn--sm" href="report.html?like=' +
      encodeURIComponent(report.id) +
      '">I&rsquo;m experiencing this too</a>' +
      '<button type="button" class="btn btn--secondary btn--sm" data-copy-link ' +
      'data-link="' +
      escape(permalink(report.id)) +
      '">Copy link</button>' +
      (context.inSheet
        ? '<a class="btn btn--ghost btn--sm" href="' +
          escape(permalink(report.id)) +
          '">Open full page</a>'
        : "") +
      "</div>" +
      '<p class="tiny muted"><a href="about.html#corrections">Report a problem with this ' +
      "report</a> — for factual disputes and takedown requests.</p>" +
      "</div>"
    );
  }

  /* ---- Nearby ------------------------------------------------------------ */

  function renderNearby(container, report, reports, facilities) {
    if (!container) return;

    var origin = { lat: report.lat, lng: report.lng };
    if (!isFinite(origin.lat) || !isFinite(origin.lng)) {
      container.innerHTML = "";
      return;
    }

    var nearReports = (reports || [])
      .filter(function (other) {
        return (
          other.id !== report.id &&
          isFinite(other.lat) &&
          metresBetween(origin, other) <= NEARBY_RADIUS_M
        );
      })
      .sort(function (a, b) {
        return metresBetween(origin, a) - metresBetween(origin, b);
      });

    var nearFacilities = (facilities || [])
      .filter(function (facility) {
        return isFinite(facility.lat) && metresBetween(origin, facility) <= NEARBY_RADIUS_M;
      })
      .sort(function (a, b) {
        return metresBetween(origin, a) - metresBetween(origin, b);
      })
      .slice(0, 8);

    var reportLine = nearReports.length
      ? '<li><strong>' +
        schema.formatNumber(nearReports.length) +
        " other report" +
        (nearReports.length === 1 ? "" : "s") +
        "</strong> within half a mile — " +
        '<a href="reports.html?district=' +
        encodeURIComponent(report.locality || "") +
        '">see them all</a></li>'
      : "<li>No other reports within half a mile.</li>";

    var facilityItems = nearFacilities.length
      ? nearFacilities
          .map(function (facility) {
            var distance = metresBetween(origin, facility);
            return (
              "<li>" +
              escape(facility.name || "Data center parcel") +
              ' <span class="badge badge--' +
              escape(facility.status) +
              '">' +
              escape(schema.statusLabel(facility.status)) +
              "</span> " +
              '<span class="tiny muted">about ' +
              (distance < 400
                ? Math.round(distance / 10) * 10 + " m"
                : (distance / 1609.344).toFixed(2) + " mi") +
              " away</span></li>"
            );
          })
          .join("")
      : "<li>No data center parcels within half a mile.</li>";

    container.innerHTML =
      '<h3 class="detail__subhead">What else is nearby</h3>' +
      '<ul class="detail__list">' +
      reportLine +
      "</ul>" +
      '<h4 class="detail__subsubhead">Data center parcels within half a mile</h4>' +
      '<ul class="detail__list">' +
      facilityItems +
      "</ul>" +
      '<p class="tiny muted">Proximity is not causation. A facility appearing here does not ' +
      "mean it caused anything the reporter described.</p>";
  }

  /* ---- Photo lightbox ---------------------------------------------------- */

  var lightbox = null;

  function openLightbox(urls, startIndex, label) {
    var index = startIndex || 0;

    if (!lightbox) {
      lightbox = document.createElement("div");
      lightbox.className = "lightbox";
      lightbox.setAttribute("role", "dialog");
      lightbox.setAttribute("aria-modal", "true");
      lightbox.setAttribute("aria-label", "Photo viewer");
      document.body.appendChild(lightbox);
    }

    function paint() {
      lightbox.innerHTML =
        '<button type="button" class="lightbox__close" aria-label="Close photo viewer">&times;</button>' +
        (urls.length > 1
          ? '<button type="button" class="lightbox__nav lightbox__nav--prev" aria-label="Previous photo">&#8249;</button>'
          : "") +
        '<img src="' +
        escape(urls[index]) +
        '" alt="' +
        escape(label || "Photo submitted with a community report") +
        " — " +
        (index + 1) +
        " of " +
        urls.length +
        '">' +
        (urls.length > 1
          ? '<button type="button" class="lightbox__nav lightbox__nav--next" aria-label="Next photo">&#8250;</button>' +
            '<p class="lightbox__count">' +
            (index + 1) +
            " of " +
            urls.length +
            "</p>"
          : "");

      lightbox.querySelector(".lightbox__close").addEventListener("click", close);
      var prev = lightbox.querySelector(".lightbox__nav--prev");
      var next = lightbox.querySelector(".lightbox__nav--next");
      if (prev) prev.addEventListener("click", function () { step(-1); });
      if (next) next.addEventListener("click", function () { step(1); });
    }

    function step(delta) {
      index = (index + delta + urls.length) % urls.length;
      paint();
    }

    function onKey(event) {
      if (event.key === "Escape") close();
      else if (event.key === "ArrowRight") step(1);
      else if (event.key === "ArrowLeft") step(-1);
      else if (event.key === "Tab") {
        // Keep focus inside the dialog. Without this, tabbing walks the page
        // behind the overlay, which for a screen reader user means the dialog
        // silently stops being where they are.
        event.preventDefault();
        var focusable = lightbox.querySelectorAll("button");
        if (!focusable.length) return;
        var current = Array.prototype.indexOf.call(focusable, document.activeElement);
        var nextIndex = (current + (event.shiftKey ? -1 : 1) + focusable.length) % focusable.length;
        focusable[nextIndex].focus();
      }
    }

    var returnFocusTo = document.activeElement;

    function close() {
      lightbox.classList.remove("is-open");
      document.body.classList.remove("has-lightbox");
      document.removeEventListener("keydown", onKey);
      lightbox.removeEventListener("click", onBackdrop);
      if (returnFocusTo && returnFocusTo.focus) returnFocusTo.focus();
    }

    function onBackdrop(event) {
      if (event.target === lightbox) close();
    }

    // Touch swipe. Only horizontal gestures count, so a vertical scroll
    // attempt on a tall photo doesn't skip to the next one.
    var touchStartX = 0;
    var touchStartY = 0;
    lightbox.addEventListener("touchstart", function (event) {
      touchStartX = event.changedTouches[0].clientX;
      touchStartY = event.changedTouches[0].clientY;
    }, { passive: true });
    lightbox.addEventListener("touchend", function (event) {
      var dx = event.changedTouches[0].clientX - touchStartX;
      var dy = event.changedTouches[0].clientY - touchStartY;
      if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) step(dx < 0 ? 1 : -1);
    }, { passive: true });

    paint();
    lightbox.classList.add("is-open");
    document.body.classList.add("has-lightbox");
    document.addEventListener("keydown", onKey);
    lightbox.addEventListener("click", onBackdrop);
    lightbox.querySelector(".lightbox__close").focus();
  }

  /* ---- Shared behaviour -------------------------------------------------- */

  function wire(root, report) {
    root.querySelectorAll("[data-photo-index]").forEach(function (button) {
      button.addEventListener("click", function () {
        openLightbox(
          report.photo_urls || [],
          Number(button.getAttribute("data-photo-index")),
          "Photo submitted with a community report in " + (report.locality || "Loudoun County")
        );
      });
    });

    var copy = root.querySelector("[data-copy-link]");
    if (copy) {
      copy.addEventListener("click", function () {
        var url = new URL(copy.getAttribute("data-link"), window.location.href).href;
        var done = function () {
          var original = copy.textContent;
          copy.textContent = "Link copied";
          setTimeout(function () {
            copy.textContent = original;
          }, 2000);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).then(done, function () {
            window.prompt("Copy this link:", url);
          });
        } else {
          window.prompt("Copy this link:", url);
        }
      });
    }
  }

  function loadNearby(root, report) {
    var slot = root.querySelector("[data-nearby]");
    if (!slot) return;
    Promise.all([
      Store.listApproved({}).catch(function () { return []; }),
      Store.loadFacilities().catch(function () { return []; }),
    ]).then(function (results) {
      renderNearby(slot, report, results[0], results[1]);
    });
  }

  /* ---- The sheet ---------------------------------------------------------- */

  var sheet = null;
  var sheetReturnFocus = null;

  function ensureSheet() {
    if (sheet) return sheet;
    sheet = document.createElement("aside");
    sheet.className = "report-sheet";
    sheet.setAttribute("role", "dialog");
    sheet.setAttribute("aria-modal", "false");
    sheet.setAttribute("aria-label", "Community report detail");
    sheet.hidden = true;
    document.body.appendChild(sheet);
    return sheet;
  }

  function closeSheet() {
    if (!sheet) return;
    sheet.classList.remove("is-open");
    sheet.hidden = true;
    document.body.classList.remove("has-sheet");
    if (sheetReturnFocus && sheetReturnFocus.focus) sheetReturnFocus.focus();
    sheetReturnFocus = null;
  }

  function openSheet(report) {
    if (!report) return;
    var node = ensureSheet();
    sheetReturnFocus = document.activeElement;

    node.innerHTML =
      '<div class="report-sheet__bar">' +
      '<button type="button" class="report-sheet__close" aria-label="Close report detail">Close</button>' +
      "</div>" +
      '<div class="report-sheet__body">' +
      detailMarkup(report, { inSheet: true, nearby: true }) +
      "</div>";

    node.hidden = false;
    // Force a frame between display and the class so the transition runs.
    void node.offsetWidth;
    node.classList.add("is-open");
    document.body.classList.add("has-sheet");

    node.querySelector(".report-sheet__close").addEventListener("click", closeSheet);
    document.addEventListener("keydown", function onEsc(event) {
      if (event.key !== "Escape") return;
      // Escape belongs to the lightbox while it is up, not to the sheet
      // underneath it.
      if (document.body.classList.contains("has-lightbox")) return;
      closeSheet();
      document.removeEventListener("keydown", onEsc);
    });

    wire(node, report);
    loadNearby(node, report);
    node.querySelector(".report-sheet__close").focus();
  }

  /* ---- Standalone page ---------------------------------------------------- */

  function mountPage() {
    var host = document.getElementById("report-detail");
    if (!host) return;

    var id = new URLSearchParams(window.location.search).get("id");
    if (!id) {
      host.innerHTML =
        '<div class="empty-state"><p class="empty-state__title">No report specified</p>' +
        '<p>This page needs a report to show.</p>' +
        '<p><a class="btn btn--primary" href="reports.html">Browse all reports</a></p></div>';
      return;
    }

    LDCW.ui.showLoading(host, "Loading this report…");

    Store.getReport(id)
      .then(function (report) {
        if (!report) {
          host.innerHTML =
            '<div class="empty-state"><p class="empty-state__title">Report not found</p>' +
            "<p>It may have been withdrawn, or the link may be wrong. Reports are only " +
            "published after a moderator approves them.</p>" +
            '<p><a class="btn btn--primary" href="reports.html">Browse all reports</a></p></div>';
          return;
        }

        host.innerHTML = detailMarkup(report, { nearby: true });
        wire(host, report);
        loadNearby(host, report);

        // Give the page a real title and description so a shared link previews
        // as this report rather than as the site's generic blurb.
        var where = report.locality || "Loudoun County";
        document.title = "Report from " + where + " — Loudoun Data Center Watch";
        var description = document.querySelector('meta[name="description"]');
        if (description) {
          description.setAttribute(
            "content",
            "A community report from " +
              where +
              ": " +
              String(report.description || "").slice(0, 150)
          );
        }

        var mapHost = document.getElementById("detail-map");
        if (mapHost && LDCW.map && isFinite(report.lat)) {
          var controller = LDCW.map.createMap("detail-map", {
            scrollWheelZoom: false,
            ariaLabel:
              "Approximate location of this report in " +
              where +
              ". The exact address is not published.",
          });
          if (controller) {
            controller.setReports([report]);
            Store.loadFacilities().then(function (facilities) {
              controller.setFacilities(facilities);
              controller.focus(report.lat, report.lng, 14);
            });
          }
        }
      })
      .catch(function (error) {
        LDCW.ui.showError(host, error.message || "Could not load this report.");
      });
  }

  /* ---- Progressive enhancement of report links ----------------------------
     Cards render a plain <a> to the report's own page, which is what happens
     without JavaScript and what a middle-click or "open in new tab" should
     still do. Here we intercept the ordinary left-click and show the sheet
     instead, so the reader keeps their place in the list.

     Delegated from the document because the list re-renders on every filter
     change — binding per card would leak handlers and miss new ones. */

  function interceptReportLinks() {
    document.addEventListener("click", function (event) {
      var link = event.target.closest ? event.target.closest("[data-report-link]") : null;
      if (!link) return;
      // Leave modified clicks alone: they mean "open this somewhere else".
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      if (event.button !== 0) return;
      // On the detail page itself the sheet would cover the same content.
      if (document.getElementById("report-detail")) return;

      event.preventDefault();
      var id = link.getAttribute("data-report-link");
      Store.getReport(id).then(function (report) {
        if (report) openSheet(report);
        else window.location.href = link.getAttribute("href");
      });
    });
  }

  LDCW.reportDetail = {
    openSheet: openSheet,
    closeSheet: closeSheet,
    detailMarkup: detailMarkup,
    openLightbox: openLightbox,
    permalink: permalink,
    mountPage: mountPage,
  };

  function boot() {
    mountPage();
    interceptReportLinks();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})(window.LDCW);
