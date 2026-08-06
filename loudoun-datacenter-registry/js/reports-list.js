/*
 * Reports page: the same records as the map, as text.
 *
 * The list and the map share one filter object and one predicate
 * (schema.matchesFilter), so what you see in each is always the same set.
 */

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var schema = LDCW.schema;
  var ui = LDCW.ui;

  var allReports = [];
  var filter = ui.readFilterFromUrl();
  var sortOrder = "newest";
  var mapController = null;

  function sortReports(reports) {
    var sorted = reports.slice();
    if (sortOrder === "oldest") {
      sorted.sort(function (a, b) {
        return new Date(a.created_at) - new Date(b.created_at);
      });
    } else if (sortOrder === "severity") {
      sorted.sort(function (a, b) {
        return (
          Number(b.severity) - Number(a.severity) ||
          new Date(b.created_at) - new Date(a.created_at)
        );
      });
    } else {
      sorted.sort(function (a, b) {
        return new Date(b.created_at) - new Date(a.created_at);
      });
    }
    return sorted;
  }

  function render() {
    var visible = allReports.filter(function (report) {
      return schema.matchesFilter(report, filter);
    });

    var count = document.getElementById("result-count");
    if (count) {
      var total = allReports.length;
      count.textContent =
        visible.length === total
          ? schema.formatNumber(total) + (total === 1 ? " report" : " reports")
          : "Showing " +
            schema.formatNumber(visible.length) +
            " of " +
            schema.formatNumber(total) +
            " reports";
    }

    ui.renderReportList(document.getElementById("report-results"), sortReports(visible));

    if (mapController) mapController.setFilter(filter);
    ui.writeFilterToUrl(filter);
  }

  function bindFilters() {
    var locality = document.getElementById("filter-locality");
    var category = document.getElementById("filter-category");
    var search = document.getElementById("filter-search");
    var reset = document.getElementById("filter-reset");
    var sort = document.getElementById("sort-order");

    ui.fillLocalitySelect(locality);
    ui.fillCategorySelect(category);

    if (locality) {
      locality.value = filter.locality || "";
      locality.addEventListener("change", function () {
        filter.locality = locality.value || undefined;
        render();
      });
    }

    if (category) {
      category.value = (filter.categories && filter.categories[0]) || "";
      category.addEventListener("change", function () {
        filter.categories = category.value ? [category.value] : undefined;
        render();
      });
    }

    if (search) {
      search.value = filter.search || "";
      search.addEventListener(
        "input",
        ui.debounce(function () {
          filter.search = search.value.trim() || undefined;
          render();
        }, 250)
      );
    }

    if (sort) {
      sort.addEventListener("change", function () {
        sortOrder = sort.value;
        render();
      });
    }

    if (reset) {
      reset.addEventListener("click", function () {
        filter = {};
        if (locality) locality.value = "";
        if (category) category.value = "";
        if (search) search.value = "";
        render();
      });
    }
  }

  function initMap() {
    LDCW.map.renderLayerToggles(document.getElementById("layer-toggles"));
    mapController = LDCW.map.createMap("map", {
      ariaLabel:
        "Map of community reports. Every report is also listed as text immediately below this map.",
      scrollWheelZoom: false,
    });
    if (!mapController) return;
    mapController.bindToggles(document.getElementById("layer-toggles"));
    mapController.setFilter(filter);

    Store.loadFacilities()
      .then(function (facilities) {
        mapController.setFacilities(facilities);
      })
      .catch(function (error) {
        console.warn("Facility layer unavailable", error);
      });
  }

  function init() {
    bindFilters();
    initMap();

    Store.listApproved({})
      .then(function (reports) {
        allReports = reports;
        if (mapController) mapController.setReports(reports);
        render();
      })
      .catch(function (error) {
        ui.showError(document.getElementById("report-results"), error);
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})(window.LDCW);
