/*
 * Statistics page.
 *
 * Charts are CSS-width <div>s inside real <table> markup. That is deliberate:
 * a screen reader reads the numbers, the page prints correctly, it theme-swaps
 * for free, and there is no charting library to vendor or keep up to date.
 */

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var schema = LDCW.schema;
  var ui = LDCW.ui;

  var latestReports = [];

  var motion = LDCW.motion;

  function setStat(name, value) {
    var node = document.querySelector('[data-stat="' + name + '"]');
    if (node) node.textContent = value;
  }

  /* Animate a numeric stat up from zero; anything non-numeric is set directly. */
  function setStatNumber(name, value, format) {
    var node = document.querySelector('[data-stat="' + name + '"]');
    if (!node) return;
    if (!isFinite(Number(value))) {
      node.textContent = "—";
      return;
    }
    motion.countUpOnView(node, Number(value), format ? { format: format } : undefined);
  }

  /* ---- Bar chart ---------------------------------------------------------- */

  function renderBarChart(tableId, rows, options) {
    var table = document.getElementById(tableId);
    if (!table) return;
    var body = table.querySelector("tbody");
    if (!body) return;

    options = options || {};

    if (!rows.length) {
      body.innerHTML =
        '<tr><td colspan="3" class="muted small">' +
        schema.escapeHtml(options.empty || "No data yet.") +
        "</td></tr>";
      return;
    }

    var max = Math.max.apply(
      null,
      rows.map(function (row) {
        return row.count;
      })
    );

    body.innerHTML = rows
      .map(function (row, rowIndex) {
        // A zero draws no bar element at all. Setting width:0 isn't enough —
        // .chart__bar carries min-width: 3px so the track would still show a
        // stub, which reads as "a small amount" rather than "none".
        var width = max && row.count ? Math.max((row.count / max) * 100, 2) : 0;
        var label = options.label ? options.label(row.key) : row.key;
        var barClass = options.barClass ? " " + options.barClass : "";
        // --stagger-index makes the bars grow in sequence when the chart
        // scrolls into view (see .is-visible .chart__bar in animations.css).
        var bar = row.count
          ? '<div class="chart__bar' +
            barClass +
            '" style="width:' +
            width.toFixed(1) +
            "%;--stagger-index:" +
            rowIndex +
            '"></div>'
          : "";
        return (
          '<tr><th scope="row" class="chart__label">' +
          schema.escapeHtml(label) +
          "</th>" +
          '<td class="chart__bar-cell"><div class="chart__track">' +
          bar +
          "</div></td>" +
          '<td class="chart__value">' +
          schema.formatNumber(row.count) +
          '<span class="muted"> · ' +
          Math.round(row.share * 100) +
          "%</span></td></tr>"
        );
      })
      .join("");
  }

  /* ---- Timeline ----------------------------------------------------------- */

  function renderTimeline(buckets) {
    var container = document.getElementById("chart-timeline");
    if (!container) return;

    var max = Math.max.apply(
      null,
      buckets.map(function (bucket) {
        return bucket.count;
      })
    );

    container.innerHTML = buckets
      .map(function (bucket, index) {
        var height = max ? Math.max((bucket.count / max) * 100, 1) : 1;
        return (
          '<div class="timeline-chart__col">' +
          '<span class="tiny numeric muted">' +
          (bucket.count || "") +
          "</span>" +
          '<div class="timeline-chart__bar" style="height:' +
          height.toFixed(1) +
          "%;--stagger-index:" +
          index +
          '"></div>' +
          '<span class="timeline-chart__label">' +
          schema.escapeHtml(bucket.label) +
          "</span>" +
          "</div>"
        );
      })
      .join("");

    // The bars are decorative; this is what a screen reader actually gets.
    var description = document.getElementById("timeline-desc");
    if (description) {
      description.textContent =
        "Reports per month over the last 12 months: " +
        buckets
          .map(function (bucket) {
            return bucket.label + " " + bucket.year + ", " + bucket.count;
          })
          .join("; ") +
        ".";
    }
  }

  /* ---- District table ----------------------------------------------------- */

  function renderDistrictTable(localities, reportsByDistrict) {
    var table = document.getElementById("table-districts");
    if (!table) return;
    var body = table.querySelector("tbody");
    if (!body) return;

    body.innerHTML = localities
      .map(function (district) {
        var facilities = district.facilities || {};
        return (
          "<tr>" +
          '<th scope="row">' +
          schema.escapeHtml(district.name) +
          "</th>" +
          '<td class="numeric">' +
          schema.formatNumber(district.population_2020) +
          "</td>" +
          '<td class="numeric">' +
          schema.formatNumber(facilities.operational || 0) +
          "</td>" +
          '<td class="numeric">' +
          schema.formatNumber(facilities.under_construction || 0) +
          "</td>" +
          '<td class="numeric">' +
          schema.formatNumber(facilities.proposed || 0) +
          "</td>" +
          '<td class="numeric">' +
          schema.formatNumber(reportsByDistrict[district.name] || 0) +
          "</td>" +
          "</tr>"
        );
      })
      .join("");
  }

  /* ---- CSV export ---------------------------------------------------------
     Only the columns already visible on the site — no contact details, no
     street addresses, and the coordinates are the jittered ones. */

  function toCsv(reports) {
    var headers = [
      "id",
      "submitted_at",
      "district",
      "zip",
      "approx_latitude",
      "approx_longitude",
      "categories",
      "impact_1_to_5",
      "occurred_on",
      "facility_status",
      "facility_name",
      "description",
    ];

    function cell(value) {
      if (value == null) return "";
      var text = String(value);
      // Prefix formula characters so spreadsheets don't execute report text.
      if (/^[=+\-@\t\r]/.test(text)) text = "'" + text;
      return '"' + text.replace(/"/g, '""') + '"';
    }

    var lines = [headers.join(",")];

    reports.forEach(function (report) {
      lines.push(
        [
          cell(report.id),
          cell(report.created_at),
          cell(report.locality),
          cell(report.zip),
          cell(report.lat),
          cell(report.lng),
          cell((report.categories || []).join("; ")),
          cell(report.severity),
          cell(report.occurred_at),
          cell(report.facility_status),
          cell(report.facility_name),
          cell(report.description),
        ].join(",")
      );
    });

    return lines.join("\r\n");
  }

  function downloadCsv() {
    var csv = toCsv(latestReports);
    // The BOM keeps Excel from mangling non-ASCII characters.
    var blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" });
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");
    link.href = url;
    link.download =
      "loudoun-data-center-watch-reports-" + new Date().toISOString().slice(0, 10) + ".csv";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    setTimeout(function () {
      URL.revokeObjectURL(url);
    }, 1000);
  }

  /* ---- Boot --------------------------------------------------------------- */

  function render(stats, localities) {
    setStatNumber("total", stats.total);
    setStatNumber("localities", stats.localityCount);
    setStatNumber("zips", stats.zipCount);
    setStatNumber("recent", stats.last30Days);
    setStat("avg-severity", stats.total ? stats.averageSeverity.toFixed(1) + " / 5" : "—");

    renderBarChart("chart-categories", stats.byCategory, {
      label: schema.categoryLabel,
      barClass: "chart__bar--reported",
      empty: "No reports published yet.",
    });

    renderBarChart("chart-localities", stats.byLocality, {
      empty: "No reports published yet.",
    });

    renderBarChart("chart-severity", stats.bySeverity, {
      label: function (key) {
        return key + " — " + schema.severityLabel(key);
      },
      empty: "No reports published yet.",
    });

    renderBarChart("chart-zips", stats.byZip.slice(0, 10), {
      empty: "No ZIP codes recorded yet.",
    });

    renderTimeline(stats.byMonth);

    if (stats.facilities) {
      setStatNumber("fac-operational", stats.facilities.counts.operational);
      setStatNumber("fac-construction", stats.facilities.counts.under_construction);
      setStatNumber("fac-proposed", stats.facilities.counts.proposed);
      // formatSqft returns null for 0, and countUp's first frame IS 0 — without
      // the fallback the tile would flash the string "null".
      setStatNumber("fac-sqft", stats.facilities.total_sqft, function (value) {
        return schema.formatSqft(value) || "0 sq ft";
      });
      setStat("generated", schema.formatDate(stats.facilities.generated));
    }

    if (localities) {
      var reportsByDistrict = {};
      stats.byLocality.forEach(function (row) {
        reportsByDistrict[row.key] = row.count;
      });
      renderDistrictTable(localities.districts || [], reportsByDistrict);
    }

    // Charts grow from zero as each scrolls into view. Observed after render so
    // the bars exist; .is-visible is what animations.css keys off.
    motion.reveal(".chart", { stagger: false });
    motion.reveal("#chart-timeline", { stagger: false });
    motion.reveal(".stat-grid", { group: true });
    motion.reveal("#table-districts", { stagger: false });
  }

  function init() {
    var button = document.getElementById("download-csv");
    if (button) button.addEventListener("click", downloadCsv);

    Promise.all([
      Store.listApproved({}),
      Store.loadSummary().catch(function () {
        return null;
      }),
      Store.loadJson("data/localities.json").catch(function () {
        return null;
      }),
    ])
      .then(function (results) {
        latestReports = results[0];
        var stats = Store.computeStats(results[0], results[1]);
        render(stats, results[2]);
      })
      .catch(function (error) {
        console.error(error);
        var main = document.getElementById("main");
        if (main) {
          var banner = document.createElement("div");
          banner.className = "container";
          banner.innerHTML =
            '<div class="banner banner--danger">' +
            ui.icon("warning") +
            "<div><strong>Couldn't load the statistics.</strong> " +
            schema.escapeHtml(error.message || "Please try again.") +
            "</div></div>";
          main.prepend(banner);
        }
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})(window.LDCW);
