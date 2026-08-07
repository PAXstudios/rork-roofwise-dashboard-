/* Home page: headline counts, the map, the concern cards, recent reports. */

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var ui = LDCW.ui;
  var schema = LDCW.schema;
  var motion = LDCW.motion;

  var mapController = null;
  var filter = ui.readFilterFromUrl();

  /* ---- Headline counts ---------------------------------------------------- */

  function statNode(name) {
    return document.querySelector('[data-stat="' + name + '"]');
  }

  function renderSummary(summary) {
    if (!summary) return;

    // Count up rather than snapping — these are the numbers the page exists to
    // make felt, and watching 103 climb reads differently from seeing it sit.
    motion.countUpOnView(statNode("operational"), summary.counts.operational);
    motion.countUpOnView(statNode("under_construction"), summary.counts.under_construction);
    motion.countUpOnView(statNode("proposed"), summary.counts.proposed);

    var generated = statNode("generated");
    if (generated) generated.textContent = "updated " + schema.formatDate(summary.generated);
  }

  /* ---- Filters ------------------------------------------------------------ */

  function applyFilter() {
    if (mapController) mapController.setFilter(filter);
    ui.writeFilterToUrl(filter);
  }

  function bindFilters() {
    var locality = document.getElementById("filter-locality");
    var category = document.getElementById("filter-category");
    var search = document.getElementById("filter-search");
    var reset = document.getElementById("filter-reset");

    ui.fillLocalitySelect(locality);
    ui.fillCategorySelect(category);

    if (locality) {
      locality.value = filter.locality || "";
      locality.addEventListener("change", function () {
        filter.locality = locality.value || undefined;
        applyFilter();
      });
    }

    if (category) {
      category.value = (filter.categories && filter.categories[0]) || "";
      category.addEventListener("change", function () {
        filter.categories = category.value ? [category.value] : undefined;
        applyFilter();
      });
    }

    if (search) {
      search.value = filter.search || "";
      search.addEventListener(
        "input",
        ui.debounce(function () {
          filter.search = search.value.trim() || undefined;
          applyFilter();
        }, 250)
      );
    }

    if (reset) {
      reset.addEventListener("click", function () {
        filter = {};
        if (locality) locality.value = "";
        if (category) category.value = "";
        if (search) search.value = "";
        applyFilter();
      });
    }
  }

  /* ---- Map ---------------------------------------------------------------- */

  function initMap() {
    LDCW.map.renderLayerToggles(document.getElementById("layer-toggles"));

    mapController = LDCW.map.createMap("map", {
      ariaLabel:
        "Map of Loudoun County data centers and community reports. The same records are listed as text on the reports and statistics pages.",
    });

    if (!mapController) return;

    mapController.bindToggles(document.getElementById("layer-toggles"));
    mapController.setFilter(filter);

    Store.loadFacilities()
      .then(function (facilities) {
        mapController.setFacilities(facilities);
      })
      .catch(function (error) {
        console.error("Facility layer failed to load", error);
        var shell = document.querySelector(".map-shell");
        if (shell) {
          var warning = document.createElement("div");
          warning.className = "banner banner--warning";
          warning.style.margin = "var(--space-3)";
          warning.innerHTML =
            ui.icon("warning") +
            "<div>The facility layer didn't load. If you opened this file directly, " +
            "serve the folder over HTTP instead — see the README.</div>";
          shell.appendChild(warning);
        }
      });
  }

  /* ---- Reports ------------------------------------------------------------ */

  function loadReports() {
    var container = document.getElementById("recent-reports");

    return Store.listApproved({})
      .then(function (reports) {
        if (mapController) mapController.setReports(reports);
        motion.countUpOnView(statNode("reports"), reports.length);

        ui.renderReportList(container, reports.slice(0, 6), {
          emptyTitle: "No community reports yet",
          emptyBody:
            "Nobody has filed a report here yet. If something is affecting you, yours can be the first.",
        });

        motion.reveal("#recent-reports .report-list", { group: true });
      })
      .catch(function (error) {
        var node = statNode("reports");
        if (node) node.textContent = "—";
        ui.showError(container, error);
      });
  }

  /* ---- Boot --------------------------------------------------------------- */

  function init() {
    ui.renderConcernCards(document.getElementById("concern-cards"));
    bindFilters();
    initMap();

    // Sections arrive as the reader scrolls to them.
    motion.reveal("#headline-stats", { group: true });
    motion.reveal("#concern-cards", { group: true });
    motion.parallax(".watermark svg", 0.18);

    Store.loadSummary()
      .then(renderSummary)
      .catch(function (error) {
        console.error("Summary failed to load", error);
      });

    loadReports();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})(window.LDCW);
