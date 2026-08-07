/*
 * Small rendering helpers shared by more than one page — report cards, filter
 * controls, empty states, icons. Keeping them here stops index, reports and
 * stats from each growing their own slightly different version of a card.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var schema = LDCW.schema;
  var escape = schema.escapeHtml;

  /* ---- Inline icons -------------------------------------------------------
     A tiny set, drawn rather than pulled from an icon font so there is no extra
     request and no flash of missing glyphs. */

  var ICONS = {
    sound:
      '<path d="M4 9v6h4l5 4V5L8 9H4Z"/><path d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"/>',
    air: '<path d="M3 8h11a3 3 0 1 0-3-3"/><path d="M3 12h15a3 3 0 1 1-3 3"/><path d="M3 16h9"/>',
    water: '<path d="M12 3s6 6.6 6 10.5a6 6 0 0 1-12 0C6 9.6 12 3 12 3Z"/>',
    power: '<path d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z"/>',
    health:
      '<path d="M12 20s-7-4.6-7-9.3A4.2 4.2 0 0 1 12 7a4.2 4.2 0 0 1 7 3.7C19 15.4 12 20 12 20Z"/>',
    home: '<path d="M4 11 12 4l8 7"/><path d="M6 10v10h12V10"/><path d="M10 20v-6h4v6"/>',
    light:
      '<path d="M9 18h6"/><path d="M10 21h4"/><path d="M12 3a6 6 0 0 1 4 10.5V16H8v-2.5A6 6 0 0 1 12 3Z"/>',
    truck:
      '<path d="M2 7h12v9H2Z"/><path d="M14 10h4l3 3v3h-7Z"/><circle cx="6" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>',
    leaf: '<path d="M4 20c0-8 5-14 16-15 0 11-6 16-13 16"/><path d="M5 19c3-4 6-6 10-8"/>',
    dots: '<circle cx="6" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="18" cy="12" r="1.4"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><path d="M12 8h.01"/>',
    warning: '<path d="M12 4 2.5 20h19L12 4Z"/><path d="M12 10v4"/><path d="M12 17h.01"/>',
    check: '<path d="m4 12 5 5L20 6"/>',
    camera:
      '<path d="M3 8h4l1.5-2h7L17 8h4v11H3Z"/><circle cx="12" cy="13" r="3.5"/>',
    pin: '<path d="M12 21s7-6.2 7-11a7 7 0 1 0-14 0c0 4.8 7 11 7 11Z"/><circle cx="12" cy="10" r="2.5"/>',
    location: '<circle cx="12" cy="12" r="8"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>',
    download: '<path d="M12 4v11"/><path d="m7 11 5 5 5-5"/><path d="M4 20h16"/>',
  };

  function icon(name, className) {
    var body = ICONS[name] || ICONS.info;
    return (
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"' +
      (className ? ' class="' + className + '"' : "") +
      ">" +
      body +
      "</svg>"
    );
  }

  /* ---- Report card -------------------------------------------------------- */

  function reportCard(report, options) {
    options = options || {};

    var categories = (report.categories || [])
      .map(function (key) {
        return '<span class="badge badge--neutral">' + escape(schema.categoryLabel(key)) + "</span>";
      })
      .join("");

    var photos = (report.photo_urls || [])
      .map(function (url) {
        return (
          '<img src="' +
          escape(url) +
          '" alt="Photo submitted with this report" loading="lazy" decoding="async">'
        );
      })
      .join("");

    var severity = Number(report.severity) || 0;

    var demoTag = report.is_demo
      ? '<span class="badge badge--pending" title="Illustrative sample, not a real submission">Sample</span>'
      : "";

    var statusTag =
      options.showStatus && report.status
        ? '<span class="badge badge--' + escape(report.status) + '">' +
          escape(report.status) +
          "</span>"
        : "";

    var where = escape(report.locality || "Loudoun County");
    if (report.zip) where += " · " + escape(report.zip);

    var facility = report.facility_name
      ? '<p class="tiny muted" style="margin-bottom:var(--space-2)">Near: ' +
        escape(report.facility_name) +
        (report.facility_status && report.facility_status !== "unknown"
          ? " (" + escape(schema.statusLabel(report.facility_status)) + ")"
          : "") +
        "</p>"
      : "";

    return (
      '<article class="report-card" data-report-id="' +
      escape(report.id) +
      '">' +
      '<div class="report-card__head">' +
      '<h3 class="report-card__where">' +
      where +
      "</h3>" +
      '<span class="report-card__when">' +
      escape(schema.formatRelative(report.created_at)) +
      "</span>" +
      "</div>" +
      facility +
      (photos ? '<div class="report-card__photos">' + photos + "</div>" : "") +
      '<p class="report-card__body">' +
      escape(report.description || "") +
      "</p>" +
      '<div class="report-card__footer">' +
      '<div class="badge-list">' +
      categories +
      demoTag +
      statusTag +
      "</div>" +
      '<span class="severity severity--' +
      severity +
      '"><span class="severity__dot" aria-hidden="true"></span>' +
      "Impact " +
      severity +
      "/5</span>" +
      "</div>" +
      "</article>"
    );
  }

  function renderReportList(container, reports, options) {
    if (!container) return;
    options = options || {};

    if (!reports.length) {
      container.innerHTML =
        '<div class="empty-state">' +
        '<p class="empty-state__title">' +
        escape(options.emptyTitle || "No reports match these filters") +
        "</p>" +
        "<p>" +
        escape(
          options.emptyBody ||
            "Try widening the filters, or be the first to report an issue in this area."
        ) +
        "</p>" +
        '<p><a class="btn btn--primary" href="report.html">Report an issue</a></p>' +
        "</div>";
      return;
    }

    container.innerHTML =
      '<ul class="report-list">' +
      reports
        .map(function (report) {
          return "<li>" + reportCard(report, options) + "</li>";
        })
        .join("") +
      "</ul>";
  }

  /* ---- Filter controls ---------------------------------------------------- */

  function fillLocalitySelect(select, extraLabel) {
    if (!select) return;
    var options = ['<option value="">' + escape(extraLabel || "All districts") + "</option>"];
    schema.LOCALITIES.forEach(function (name) {
      options.push('<option value="' + escape(name) + '">' + escape(name) + "</option>");
    });
    select.innerHTML = options.join("");
  }

  function fillCategorySelect(select, extraLabel) {
    if (!select) return;
    var options = ['<option value="">' + escape(extraLabel || "All issues") + "</option>"];
    schema.CATEGORIES.forEach(function (category) {
      options.push(
        '<option value="' + escape(category.key) + '">' + escape(category.label) + "</option>"
      );
    });
    select.innerHTML = options.join("");
  }

  /* ---- Concern cards ------------------------------------------------------ */

  function renderConcernCards(container) {
    if (!container) return;
    container.innerHTML = schema.CATEGORIES.filter(function (category) {
      return category.key !== "other";
    })
      .map(function (category) {
        return (
          '<a class="concern-card" href="reports.html?category=' +
          encodeURIComponent(category.key) +
          '">' +
          icon(category.icon, "concern-card__icon") +
          '<h3 class="concern-card__title">' +
          escape(category.label) +
          "</h3>" +
          '<p class="small muted" style="margin:0">' +
          escape(category.note) +
          "</p>" +
          "</a>"
        );
      })
      .join("");
  }

  /* ---- States ------------------------------------------------------------- */

  function showLoading(container, message) {
    if (!container) return;
    container.innerHTML =
      '<div class="loading"><span class="spinner"></span>' +
      escape(message || "Loading…") +
      "</div>";
  }

  function showError(container, error) {
    if (!container) return;
    container.innerHTML =
      '<div class="banner banner--danger">' +
      icon("warning") +
      "<div><strong>Something went wrong.</strong> " +
      escape((error && error.message) || "Please try again.") +
      "</div></div>";
    if (error) console.error(error);
  }

  /* ---- URL state ----------------------------------------------------------
     Filters are reflected in the query string so a filtered view can be shared
     or linked to from the concern cards. */

  function readFilterFromUrl() {
    var params = new URLSearchParams(window.location.search);
    var filter = {};
    if (params.get("locality")) filter.locality = params.get("locality");
    if (params.get("category")) filter.categories = [params.get("category")];
    if (params.get("status")) filter.facilityStatus = params.get("status");
    if (params.get("q")) filter.search = params.get("q");
    return filter;
  }

  function writeFilterToUrl(filter) {
    var params = new URLSearchParams();
    if (filter.locality) params.set("locality", filter.locality);
    if (filter.categories && filter.categories.length) {
      params.set("category", filter.categories[0]);
    }
    if (filter.facilityStatus) params.set("status", filter.facilityStatus);
    if (filter.search) params.set("q", filter.search);

    var query = params.toString();
    var url = window.location.pathname + (query ? "?" + query : "");
    window.history.replaceState(null, "", url);
  }

  function debounce(fn, wait) {
    var timer = null;
    return function () {
      var args = arguments;
      var self = this;
      clearTimeout(timer);
      timer = setTimeout(function () {
        fn.apply(self, args);
      }, wait);
    };
  }

  LDCW.ui = {
    icon: icon,
    ICONS: ICONS,
    reportCard: reportCard,
    renderReportList: renderReportList,
    fillLocalitySelect: fillLocalitySelect,
    fillCategorySelect: fillCategorySelect,
    renderConcernCards: renderConcernCards,
    showLoading: showLoading,
    showError: showError,
    readFilterFromUrl: readFilterFromUrl,
    writeFilterToUrl: writeFilterToUrl,
    debounce: debounce,
  };
})(window.LDCW);
