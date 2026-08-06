/*
 * Shared vocabulary and validation.
 *
 * Every page reads its category lists, status labels, filter logic and
 * formatting helpers from here, so the map, the list and the statistics page
 * can never drift out of agreement about what a report is.
 *
 * Exposed as window.LDCW.schema — no build step, so no modules.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  /* ---- Issue categories -------------------------------------------------
     Ordered roughly by how often they come up in Loudoun board meetings and
     local reporting. `key` is what gets stored; never rename one without a
     migration, because it lives in the database. */

  var CATEGORIES = [
    {
      key: "noise",
      label: "Noise",
      note: "Constant hum, fans, chillers, generator testing",
      icon: "sound",
    },
    {
      key: "air_quality",
      label: "Air quality & diesel fumes",
      note: "Generator exhaust, smells, visible haze",
      icon: "air",
    },
    {
      key: "water",
      label: "Water",
      note: "Supply, wells, runoff, stream or pond changes",
      icon: "water",
    },
    {
      key: "power",
      label: "Electricity & grid",
      note: "Outages, flicker, transmission lines, bills",
      icon: "power",
    },
    {
      key: "health",
      label: "Health",
      note: "Sleep loss, headaches, breathing, stress",
      icon: "health",
    },
    {
      key: "property",
      label: "Property values & views",
      note: "Sale prices, buyers walking, loss of outlook",
      icon: "home",
    },
    {
      key: "light",
      label: "Light pollution",
      note: "Floodlights, security lighting at night",
      icon: "light",
    },
    {
      key: "traffic",
      label: "Traffic & construction",
      note: "Trucks, road damage, dust, work hours",
      icon: "truck",
    },
    {
      key: "wildlife",
      label: "Wildlife & land",
      note: "Tree loss, habitat, farmland, streams",
      icon: "leaf",
    },
    {
      key: "other",
      label: "Something else",
      note: "Anything not covered above",
      icon: "dots",
    },
  ];

  var CATEGORY_BY_KEY = {};
  CATEGORIES.forEach(function (category) {
    CATEGORY_BY_KEY[category.key] = category;
  });

  /* ---- Facility status --------------------------------------------------- */

  var FACILITY_STATUSES = [
    {
      key: "operational",
      label: "Operational",
      note: "Built and running",
      swatch: "operational",
    },
    {
      key: "under_construction",
      label: "Under construction",
      note: "Approved and being built",
      swatch: "under_construction",
    },
    {
      key: "proposed",
      label: "Proposed",
      note: "In the county's approval pipeline",
      swatch: "proposed",
    },
    {
      key: "unknown",
      label: "Not sure",
      note: "",
      swatch: "unknown",
    },
  ];

  var REPORT_STATUSES = ["pending", "approved", "rejected"];

  /* ---- Severity ---------------------------------------------------------- */

  var SEVERITY_LABELS = {
    1: "Barely noticeable",
    2: "Noticeable",
    3: "Disruptive",
    4: "Hard to live with",
    5: "Severe",
  };

  /* ---- Localities --------------------------------------------------------
     Loudoun's eight election districts. These are what the county's own
     facility data is tagged with, so using them keeps citizen reports and
     county records in the same buckets. */

  var LOCALITIES = [
    "Algonkian",
    "Ashburn",
    "Blue Ridge",
    "Broad Run",
    "Catoctin",
    "Dulles",
    "Leesburg",
    "Little River",
    "Sterling",
  ];

  /* ---- Validation --------------------------------------------------------
     Mirrors the CHECK constraints in sql/01_schema.sql. Client-side validation
     is for helpful errors; the database is what actually enforces this. */

  var LIMITS = {
    descriptionMin: 20,
    descriptionMax: 5000,
    notesMax: 2000,
    categoriesMin: 1,
    categoriesMax: 10,
    // Loudoun County bounding box.
    latMin: 38.8,
    latMax: 39.4,
    lngMin: -78.05,
    lngMax: -77.2,
  };

  function validateReport(draft) {
    var errors = {};

    if (!draft.locality || LOCALITIES.indexOf(draft.locality) === -1) {
      errors.locality = "Choose the district you're reporting from.";
    }

    if (draft.zip && !/^\d{5}$/.test(draft.zip)) {
      errors.zip = "Enter a 5-digit ZIP code, or leave this blank.";
    }

    var lat = Number(draft.lat);
    var lng = Number(draft.lng);
    if (!isFinite(lat) || !isFinite(lng)) {
      errors.location = "Set the location on the map before submitting.";
    } else if (
      lat < LIMITS.latMin ||
      lat > LIMITS.latMax ||
      lng < LIMITS.lngMin ||
      lng > LIMITS.lngMax
    ) {
      errors.location =
        "That location is outside Loudoun County. This site only collects Loudoun reports.";
    }

    var categories = draft.categories || [];
    if (categories.length < LIMITS.categoriesMin) {
      errors.categories = "Pick at least one kind of issue.";
    } else if (categories.length > LIMITS.categoriesMax) {
      errors.categories = "That's more categories than exist.";
    } else {
      var unknown = categories.filter(function (key) {
        return !CATEGORY_BY_KEY[key];
      });
      if (unknown.length) {
        errors.categories = "Unrecognised category: " + unknown.join(", ");
      }
    }

    var severity = Number(draft.severity);
    if (!(severity >= 1 && severity <= 5)) {
      errors.severity = "Rate how much this affects you, from 1 to 5.";
    }

    var description = (draft.description || "").trim();
    if (description.length < LIMITS.descriptionMin) {
      errors.description =
        "Please describe what you're experiencing in at least " +
        LIMITS.descriptionMin +
        " characters.";
    } else if (description.length > LIMITS.descriptionMax) {
      errors.description = "Please keep this under " + LIMITS.descriptionMax + " characters.";
    }

    if ((draft.other_notes || "").length > LIMITS.notesMax) {
      errors.other_notes = "Please keep this under " + LIMITS.notesMax + " characters.";
    }

    if (draft.reporter_email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(draft.reporter_email)) {
      errors.reporter_email = "That doesn't look like an email address.";
    }

    if (draft.occurred_at) {
      var when = new Date(draft.occurred_at);
      if (isNaN(when.getTime())) {
        errors.occurred_at = "That date isn't valid.";
      } else if (when.getTime() > Date.now() + 86400000) {
        errors.occurred_at = "That date is in the future.";
      }
    }

    if (!draft.accepted_terms) {
      errors.accepted_terms = "Please confirm you've read how your report will be used.";
    }

    return { valid: Object.keys(errors).length === 0, errors: errors };
  }

  /* ---- Filtering ---------------------------------------------------------
     One predicate, used by the map and the list alike. */

  function matchesFilter(report, filter) {
    if (!filter) return true;

    if (filter.locality && report.locality !== filter.locality) return false;

    if (filter.categories && filter.categories.length) {
      var reportCategories = report.categories || [];
      var hit = filter.categories.some(function (key) {
        return reportCategories.indexOf(key) !== -1;
      });
      if (!hit) return false;
    }

    if (filter.facilityStatus && report.facility_status !== filter.facilityStatus) return false;

    if (filter.minSeverity && Number(report.severity) < Number(filter.minSeverity)) return false;

    if (filter.since) {
      var since = new Date(filter.since).getTime();
      var created = new Date(report.created_at).getTime();
      if (isFinite(since) && created < since) return false;
    }

    if (filter.search) {
      var needle = filter.search.toLowerCase();
      var haystack = [
        report.description,
        report.facility_name,
        report.facility_operator,
        report.locality,
        report.zip,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      if (haystack.indexOf(needle) === -1) return false;
    }

    return true;
  }

  function matchesFacilityFilter(facility, filter) {
    if (!filter) return true;
    if (filter.locality && facility.district !== filter.locality) return false;
    if (filter.facilityStatus && facility.status !== filter.facilityStatus) return false;
    if (filter.search) {
      var needle = filter.search.toLowerCase();
      var haystack = [facility.name, facility.operator, facility.district, facility.zoning_case]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      if (haystack.indexOf(needle) === -1) return false;
    }
    return true;
  }

  /* ---- Formatting -------------------------------------------------------- */

  function categoryLabel(key) {
    var category = CATEGORY_BY_KEY[key];
    return category ? category.label : key;
  }

  function statusLabel(key) {
    for (var i = 0; i < FACILITY_STATUSES.length; i++) {
      if (FACILITY_STATUSES[i].key === key) return FACILITY_STATUSES[i].label;
    }
    return "Unknown";
  }

  function severityLabel(value) {
    return SEVERITY_LABELS[Number(value)] || "";
  }

  function formatNumber(value) {
    if (value == null || !isFinite(Number(value))) return "—";
    return Number(value).toLocaleString("en-US");
  }

  function formatSqft(value) {
    if (!value || !isFinite(Number(value))) return null;
    var number = Number(value);
    if (number >= 1000000) return (number / 1000000).toFixed(1) + "M sq ft";
    if (number >= 1000) return Math.round(number / 1000) + "K sq ft";
    return formatNumber(number) + " sq ft";
  }

  function formatDate(value) {
    if (!value) return "";
    var date = new Date(value);
    if (isNaN(date.getTime())) return "";
    return date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  }

  function formatRelative(value) {
    if (!value) return "";
    var date = new Date(value);
    if (isNaN(date.getTime())) return "";
    var seconds = Math.floor((Date.now() - date.getTime()) / 1000);
    if (seconds < 60) return "just now";
    var minutes = Math.floor(seconds / 60);
    if (minutes < 60) return minutes + (minutes === 1 ? " minute ago" : " minutes ago");
    var hours = Math.floor(minutes / 60);
    if (hours < 24) return hours + (hours === 1 ? " hour ago" : " hours ago");
    var days = Math.floor(hours / 24);
    if (days < 30) return days + (days === 1 ? " day ago" : " days ago");
    var months = Math.floor(days / 30);
    if (months < 12) return months + (months === 1 ? " month ago" : " months ago");
    return formatDate(value);
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  /* ---- Privacy -----------------------------------------------------------
     Reports are plotted at an offset position so a pin can't be walked back to
     a front door. In Supabase mode a database trigger does this server-side and
     the exact coordinates never leave the row; this function is the demo-mode
     equivalent and the reference implementation for the SQL. */

  function jitterCoordinates(lat, lng) {
    var config = window.LDCW_CONFIG || {};
    var minMetres = config.LOCATION_JITTER_MIN_M || 100;
    var maxMetres = config.LOCATION_JITTER_MAX_M || 200;

    var distance = minMetres + Math.random() * (maxMetres - minMetres);
    var bearing = Math.random() * 2 * Math.PI;

    var deltaLat = (distance * Math.cos(bearing)) / 111320;
    var deltaLng =
      (distance * Math.sin(bearing)) / (111320 * Math.cos((lat * Math.PI) / 180) || 1);

    return {
      lat: Math.round((lat + deltaLat) * 1000000) / 1000000,
      lng: Math.round((lng + deltaLng) * 1000000) / 1000000,
    };
  }

  /* Strip everything that must never be published, whichever backend produced
     the row. Belt and braces: the Supabase view already excludes these. */
  function toPublicReport(report) {
    return {
      id: report.id,
      created_at: report.created_at,
      locality: report.locality,
      zip: report.zip || null,
      lat: report.lat_public,
      lng: report.lng_public,
      facility_name: report.facility_name || null,
      facility_operator: report.facility_operator || null,
      facility_status: report.facility_status || "unknown",
      categories: report.categories || [],
      severity: report.severity,
      occurred_at: report.occurred_at || null,
      description: report.description,
      other_notes: report.other_notes || null,
      photo_urls: report.photo_urls || [],
      is_demo: report.is_demo === true,
    };
  }

  LDCW.schema = {
    CATEGORIES: CATEGORIES,
    CATEGORY_BY_KEY: CATEGORY_BY_KEY,
    FACILITY_STATUSES: FACILITY_STATUSES,
    REPORT_STATUSES: REPORT_STATUSES,
    SEVERITY_LABELS: SEVERITY_LABELS,
    LOCALITIES: LOCALITIES,
    LIMITS: LIMITS,
    validateReport: validateReport,
    matchesFilter: matchesFilter,
    matchesFacilityFilter: matchesFacilityFilter,
    categoryLabel: categoryLabel,
    statusLabel: statusLabel,
    severityLabel: severityLabel,
    formatNumber: formatNumber,
    formatSqft: formatSqft,
    formatDate: formatDate,
    formatRelative: formatRelative,
    escapeHtml: escapeHtml,
    jitterCoordinates: jitterCoordinates,
    toPublicReport: toPublicReport,
  };
})(window.LDCW);
