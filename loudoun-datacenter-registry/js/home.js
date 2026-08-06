/* Home page: headline counts, the map, the concern cards, recent reports. */

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var ui = LDCW.ui;
  var schema = LDCW.schema;

  var mapController = null;
  var filter = ui.readFilterFromUrl();

  /* ---- Headline counts ---------------------------------------------------- */

  function setStat(name, value) {
    var node = document.querySelector('[data-stat="' + name + '"]');
    if (node) node.textContent = value;
  }

  function renderSummary(summary) {
    if (!summary) return;
    setStat("operational", schema.formatNumber(summary.counts.operational));
    setStat("under_construction", schema.formatNumber(summary.counts.under_construction));
    setStat("proposed", schema.formatNumber(summary.counts.proposed));
    setStat("generated", "updated " + schema.formatDate(summary.generated));
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
            LDCW.ui.icon("warning") +
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
        setStat("reports", schema.formatNumber(reports.length));
        ui.renderReportList(container, reports.slice(0, 6), {
          emptyTitle: "No community reports yet",
          emptyBody:
            "Nobody has filed a report here yet. If something is affecting you, yours can be the first.",
        });
      })
      .catch(function (error) {
        setStat("reports", "—");
        ui.showError(container, error);
      });
  }

  /* ---- Boot --------------------------------------------------------------- */

  function init() {
    ui.renderConcernCards(document.getElementById("concern-cards"));
    bindFilters();
    initMap();

    Store.loadSummary().then(renderSummary).catch(function (error) {
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
