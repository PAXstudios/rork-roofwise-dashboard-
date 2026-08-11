/*
 * The report form.
 *
 * Three things here are worth knowing about:
 *
 * 1. Location. Three ways to set it — device GPS, tapping the map, or an
 *    address search — because the person filling this in may be standing in
 *    their garden on a phone or sitting at a desk. The pin is what's required;
 *    the typed address is optional and never published.
 *
 * 2. Photos. Re-encoded through a <canvas> before upload, which strips EXIF.
 *    Phone photos carry GPS coordinates, and publishing those would defeat the
 *    coordinate jitter that protects the household.
 *
 * 3. Anti-spam. A honeypot, a minimum time-on-form, and a client-side rate
 *    limit. None of these is strong on its own — moderation is what actually
 *    keeps the public map clean — but together they stop casual automation.
 */

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var schema = LDCW.schema;
  var ui = LDCW.ui;
  var config = window.LDCW_CONFIG || {};

  var form = document.getElementById("report-form");
  if (!form) return;

  var formLoadedAt = Date.now();
  var lastGeocodeAt = 0;
  var districts = null;
  var selectedFiles = [];
  var pickMap = null;
  var pickMarker = null;
  var location = { lat: null, lng: null };

  /* ==================================================================== */
  /* Field rendering                                                       */
  /* ==================================================================== */

  function renderCategories() {
    var container = document.getElementById("categories");
    if (!container) return;
    container.innerHTML = schema.CATEGORIES.map(function (category) {
      return (
        '<label class="choice" for="cat-' +
        category.key +
        '">' +
        '<input type="checkbox" id="cat-' +
        category.key +
        '" name="categories" value="' +
        category.key +
        '">' +
        '<span class="choice__text">' +
        '<span class="choice__title">' +
        schema.escapeHtml(category.label) +
        "</span>" +
        (category.note
          ? '<span class="choice__note">' + schema.escapeHtml(category.note) + "</span>"
          : "") +
        "</span></label>"
      );
    }).join("");
  }

  function renderSeverity() {
    var container = document.getElementById("severity");
    if (!container) return;
    container.innerHTML = [1, 2, 3, 4, 5]
      .map(function (level) {
        return (
          '<label class="severity-scale__option">' +
          '<input type="radio" name="severity" value="' +
          level +
          '" aria-label="' +
          level +
          " — " +
          schema.escapeHtml(schema.severityLabel(level)) +
          '">' +
          "<span>" +
          level +
          "</span></label>"
        );
      })
      .join("");
  }

  function renderFacilityStatus() {
    var container = document.getElementById("facility-status");
    if (!container) return;
    // "Not sure" first and pre-selected: most people genuinely don't know, and
    // making that the default stops the field from being a guessing game.
    var order = ["unknown", "operational", "under_construction", "proposed"];
    container.innerHTML = order
      .map(function (key, index) {
        var status = schema.FACILITY_STATUSES.filter(function (item) {
          return item.key === key;
        })[0];
        if (!status) return "";
        var label = key === "unknown" ? "I'm not sure" : status.label;
        return (
          '<label class="choice" for="fs-' +
          key +
          '">' +
          '<input type="radio" id="fs-' +
          key +
          '" name="facility_status" value="' +
          key +
          '"' +
          (index === 0 ? " checked" : "") +
          ">" +
          '<span class="choice__text"><span class="choice__title">' +
          schema.escapeHtml(label) +
          "</span>" +
          (status.note
            ? '<span class="choice__note">' + schema.escapeHtml(status.note) + "</span>"
            : "") +
          "</span></label>"
        );
      })
      .join("");
  }

  /* ==================================================================== */
  /* Location                                                              */
  /* ==================================================================== */

  function setStatus(message) {
    var node = document.getElementById("location-status");
    if (node) node.textContent = message;
  }

  /* Ray-casting point-in-polygon, run against the district boundaries that
     ship with the site. Keeps district assignment offline and instant. */
  function pointInRing(lng, lat, ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      var xi = ring[i][0];
      var yi = ring[i][1];
      var xj = ring[j][0];
      var yj = ring[j][1];
      if (yi > lat !== yj > lat) {
        var crossing = ((xj - xi) * (lat - yi)) / (yj - yi) + xi;
        if (lng < crossing) inside = !inside;
      }
    }
    return inside;
  }

  function ringsOf(geometry) {
    if (!geometry) return [];
    if (geometry.type === "Polygon") return geometry.coordinates.slice(0, 1);
    if (geometry.type === "MultiPolygon") {
      return geometry.coordinates.map(function (polygon) {
        return polygon[0];
      });
    }
    return [];
  }

  function districtFor(lat, lng) {
    if (!districts) return null;
    for (var i = 0; i < districts.features.length; i++) {
      var feature = districts.features[i];
      var rings = ringsOf(feature.geometry);
      for (var r = 0; r < rings.length; r++) {
        if (pointInRing(lng, lat, rings[r])) return feature.properties.name;
      }
    }
    return null;
  }

  function setLocation(lat, lng, source) {
    location.lat = lat;
    location.lng = lng;

    if (pickMap) {
      var latlng = [lat, lng];
      if (!pickMarker) {
        pickMarker = L.marker(latlng, {
          draggable: true,
          icon: L.divIcon({
            className: "",
            html: '<span class="pin pin--report"></span>',
            iconSize: [18, 18],
            iconAnchor: [9, 18],
          }),
        }).addTo(pickMap);

        pickMarker.on("dragend", function () {
          var position = pickMarker.getLatLng();
          setLocation(position.lat, position.lng, "drag");
        });
      } else {
        pickMarker.setLatLng(latlng);
      }
      pickMap.setView(latlng, Math.max(pickMap.getZoom(), 14));
    }

    var district = districtFor(lat, lng);
    var localitySelect = document.getElementById("locality");

    if (district && localitySelect) {
      // Don't stomp a district the person deliberately chose themselves.
      if (!localitySelect.value || localitySelect.dataset.autofilled === "true") {
        localitySelect.value = district;
        localitySelect.dataset.autofilled = "true";
      }
    }

    var inCounty = district != null;
    var descriptions = {
      geolocate: "Using your device location",
      map: "Pin placed on the map",
      drag: "Pin moved",
      address: "Found from the address you entered",
    };

    setStatus(
      (descriptions[source] || "Location set") +
        ": " +
        lat.toFixed(5) +
        ", " +
        lng.toFixed(5) +
        (inCounty
          ? " — " + district + " district."
          : " — this looks like it's outside Loudoun County.")
    );

    clearError("location");
  }

  function initPickMap() {
    var element = document.getElementById("pick-map");
    if (!element || typeof L === "undefined") return;

    pickMap = L.map(element, {
      center: config.MAP_CENTER,
      zoom: 10,
      minZoom: config.MAP_MIN_ZOOM,
      scrollWheelZoom: false,
    });

    element.setAttribute("role", "application");
    element.setAttribute(
      "aria-label",
      "Map for choosing the report location. You can also use the 'Use my location' button or the address search instead."
    );

    L.tileLayer(config.TILE_URL, {
      attribution: config.TILE_ATTRIBUTION,
      maxZoom: 19,
    }).addTo(pickMap);

    pickMap.on("click", function (event) {
      setLocation(event.latlng.lat, event.latlng.lng, "map");
    });

    setTimeout(function () {
      pickMap.invalidateSize();
    }, 250);

    Store.loadJson("data/districts.geojson")
      .then(function (data) {
        districts = data;
        L.geoJSON(data, {
          style: {
            color: "#7b879b",
            weight: 1,
            fillOpacity: 0.04,
            interactive: false,
          },
        }).addTo(pickMap);
      })
      .catch(function (error) {
        // Not fatal: the district select just won't auto-fill.
        console.warn("District boundaries unavailable", error);
      });
  }

  function useMyLocation() {
    if (!navigator.geolocation) {
      setStatus("This browser can't share your location. Tap the map instead.");
      return;
    }

    setStatus("Asking your browser for your location…");

    navigator.geolocation.getCurrentPosition(
      function (position) {
        setLocation(position.coords.latitude, position.coords.longitude, "geolocate");
      },
      function (error) {
        var messages = {
          1: "Location permission was denied. Tap the map to place a pin instead.",
          2: "Your location isn't available right now. Tap the map instead.",
          3: "Finding your location took too long. Tap the map instead.",
        };
        setStatus(messages[error.code] || "Couldn't get your location. Tap the map instead.");
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 }
    );
  }

  /* Nominatim allows about one request per second and forbids bulk use, so this
     only ever runs on an explicit button press — never as you type. */
  function findAddress() {
    var input = document.getElementById("address-input");
    if (!input || !input.value.trim()) {
      setStatus("Type an address first, then press Find.");
      return;
    }

    var sinceLast = Date.now() - lastGeocodeAt;
    var minimum = config.GEOCODE_MIN_INTERVAL_MS || 1100;
    if (sinceLast < minimum) {
      setStatus("One moment — address lookups are limited to one per second.");
      return;
    }
    lastGeocodeAt = Date.now();

    setStatus("Looking up that address…");

    var bounds = config.MAP_BOUNDS;
    var params = new URLSearchParams({
      q: input.value.trim() + ", Loudoun County, Virginia",
      format: "jsonv2",
      limit: "1",
      countrycodes: "us",
      viewbox: [bounds[0][1], bounds[1][0], bounds[1][1], bounds[0][0]].join(","),
      bounded: "1",
    });

    fetch(config.GEOCODE_URL + "?" + params.toString(), {
      headers: { Accept: "application/json" },
    })
      .then(function (response) {
        if (!response.ok) throw new Error("Address lookup failed (" + response.status + ").");
        return response.json();
      })
      .then(function (results) {
        if (!results.length) {
          setStatus("Couldn't find that address. Tap the map to place a pin instead.");
          return;
        }
        setLocation(parseFloat(results[0].lat), parseFloat(results[0].lon), "address");
      })
      .catch(function () {
        setStatus(
          "The address service didn't respond. Tap the map to place a pin instead — that always works."
        );
      });
  }

  /* ==================================================================== */
  /* Photos                                                                */
  /* ==================================================================== */

  /* Re-encoding through a canvas discards every metadata block, including the
     GPS tags that phones write. It also caps the dimensions, which keeps
     uploads small. */
  function stripMetadata(file) {
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(file);
      var image = new Image();

      image.onload = function () {
        URL.revokeObjectURL(url);

        var maxEdge = config.MAX_PHOTO_DIMENSION || 2000;
        var scale = Math.min(1, maxEdge / Math.max(image.width, image.height));
        var canvas = document.createElement("canvas");
        canvas.width = Math.round(image.width * scale);
        canvas.height = Math.round(image.height * scale);

        var context = canvas.getContext("2d");
        context.drawImage(image, 0, 0, canvas.width, canvas.height);

        canvas.toBlob(
          function (blob) {
            if (!blob) {
              reject(new Error("Couldn't process " + file.name + "."));
              return;
            }
            var cleaned = new File([blob], file.name.replace(/\.\w+$/, "") + ".jpg", {
              type: "image/jpeg",
              lastModified: Date.now(),
            });
            resolve(cleaned);
          },
          "image/jpeg",
          0.85
        );
      };

      image.onerror = function () {
        URL.revokeObjectURL(url);
        // Most likely a HEIC on a browser that can't decode it. Refusing is the
        // right call: uploading the original would carry its GPS tags through.
        reject(
          new Error(
            "This browser can't read " +
              file.name +
              ". Please convert it to JPG or PNG and try again."
          )
        );
      };

      image.src = url;
    });
  }

  function renderPreviews() {
    var container = document.getElementById("photo-previews");
    if (!container) return;

    container.innerHTML = selectedFiles
      .map(function (entry, index) {
        return (
          '<div class="photo-preview">' +
          '<img src="' +
          entry.preview +
          '" alt="Preview of ' +
          schema.escapeHtml(entry.file.name) +
          '">' +
          '<button class="photo-preview__remove" type="button" data-remove="' +
          index +
          '" aria-label="Remove ' +
          schema.escapeHtml(entry.file.name) +
          '">&times;</button>' +
          '<span class="photo-preview__name">' +
          schema.escapeHtml(entry.file.name) +
          "</span>" +
          "</div>"
        );
      })
      .join("");

    container.querySelectorAll("[data-remove]").forEach(function (button) {
      button.addEventListener("click", function () {
        var index = Number(button.getAttribute("data-remove"));
        URL.revokeObjectURL(selectedFiles[index].preview);
        selectedFiles.splice(index, 1);
        renderPreviews();
        clearError("photos");
      });
    });
  }

  function addFiles(fileList) {
    var maxPhotos = config.MAX_PHOTOS || 5;
    var maxBytes = config.MAX_PHOTO_BYTES || 10 * 1024 * 1024;
    var incoming = Array.prototype.slice.call(fileList);
    var problems = [];

    var room = maxPhotos - selectedFiles.length;
    if (incoming.length > room) {
      problems.push("You can attach up to " + maxPhotos + " photos.");
      incoming = incoming.slice(0, Math.max(room, 0));
    }

    var accepted = incoming.filter(function (file) {
      if (!/^image\//.test(file.type)) {
        problems.push(file.name + " isn't an image.");
        return false;
      }
      if (file.size > maxBytes) {
        problems.push(
          file.name + " is larger than " + Math.round(maxBytes / 1024 / 1024) + " MB."
        );
        return false;
      }
      return true;
    });

    showError("photos", problems.join(" "));
    if (!accepted.length) return;

    Promise.all(
      accepted.map(function (file) {
        return stripMetadata(file)
          .then(function (cleaned) {
            return { file: cleaned, preview: URL.createObjectURL(cleaned) };
          })
          .catch(function (error) {
            problems.push(error.message);
            return null;
          });
      })
    ).then(function (entries) {
      entries.filter(Boolean).forEach(function (entry) {
        selectedFiles.push(entry);
      });
      renderPreviews();
      showError("photos", problems.join(" "));
    });
  }

  function initPhotos() {
    var drop = document.getElementById("photo-drop");
    var input = document.getElementById("photos");
    if (!drop || !input) return;

    drop.addEventListener("click", function () {
      input.click();
    });

    drop.addEventListener("keydown", function (event) {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        input.click();
      }
    });

    input.addEventListener("change", function () {
      addFiles(input.files);
      input.value = "";
    });

    ["dragenter", "dragover"].forEach(function (name) {
      drop.addEventListener(name, function (event) {
        event.preventDefault();
        drop.classList.add("is-dragover");
      });
    });

    ["dragleave", "drop"].forEach(function (name) {
      drop.addEventListener(name, function (event) {
        event.preventDefault();
        drop.classList.remove("is-dragover");
      });
    });

    drop.addEventListener("drop", function (event) {
      if (event.dataTransfer && event.dataTransfer.files) addFiles(event.dataTransfer.files);
    });
  }

  /* ==================================================================== */
  /* Errors                                                                */
  /* ==================================================================== */

  var FIELD_CONTAINERS = {
    location: "error-location",
    locality: "error-locality",
    zip: "error-zip",
    categories: "error-categories",
    severity: "error-severity",
    description: "error-description",
    occurred_at: "error-occurred_at",
    other_notes: "error-other_notes",
    reporter_email: "error-reporter_email",
    accepted_terms: "error-accepted_terms",
    photos: "error-photos",
  };

  function showError(field, message) {
    var node = document.getElementById(FIELD_CONTAINERS[field]);
    if (!node) return;
    node.textContent = message || "";
    var wrapper = node.closest(".field");
    if (wrapper) wrapper.classList.toggle("field--invalid", Boolean(message));
  }

  function clearError(field) {
    showError(field, "");
  }

  function clearAllErrors() {
    Object.keys(FIELD_CONTAINERS).forEach(clearError);
  }

  var FOCUS_TARGETS = {
    location: "use-my-location",
    locality: "locality",
    zip: "zip",
    categories: "cat-noise",
    severity: "severity",
    description: "description",
    occurred_at: "occurred_at",
    other_notes: "other_notes",
    reporter_email: "reporter_email",
    accepted_terms: "accepted_terms",
  };

  function focusFirstError(errors) {
    var order = Object.keys(FIELD_CONTAINERS);
    for (var i = 0; i < order.length; i++) {
      if (errors[order[i]]) {
        var target = document.getElementById(FOCUS_TARGETS[order[i]]);
        if (target) {
          var focusable = target.matches("input, select, textarea, button")
            ? target
            : target.querySelector("input, select, textarea, button");
          if (focusable) focusable.focus();
          target.scrollIntoView({ behavior: "smooth", block: "center" });
        }
        return;
      }
    }
  }

  /* ==================================================================== */
  /* Submission                                                            */
  /* ==================================================================== */

  function collect() {
    var categories = Array.prototype.slice
      .call(form.querySelectorAll('input[name="categories"]:checked'))
      .map(function (input) {
        return input.value;
      });

    var severity = form.querySelector('input[name="severity"]:checked');
    var facilityStatus = form.querySelector('input[name="facility_status"]:checked');

    function value(id) {
      var node = document.getElementById(id);
      return node ? node.value.trim() : "";
    }

    return {
      locality: value("locality"),
      zip: value("zip"),
      address: value("address-input"),
      lat: location.lat,
      lng: location.lng,
      facility_name: value("facility_name"),
      facility_operator: value("facility_operator"),
      facility_status: facilityStatus ? facilityStatus.value : "unknown",
      categories: categories,
      severity: severity ? Number(severity.value) : null,
      occurred_at: value("occurred_at") || null,
      description: value("description"),
      other_notes: value("other_notes"),
      reporter_name: value("reporter_name"),
      reporter_email: value("reporter_email"),
      reporter_phone: value("reporter_phone"),
      contact_ok: document.getElementById("contact_ok").checked,
      accepted_terms: document.getElementById("accepted_terms").checked,
    };
  }

  function setFormStatus(message, kind) {
    var node = document.getElementById("form-status");
    if (!node) return;
    node.textContent = message || "";
    node.className = "form-status" + (kind ? " form-status--" + kind : "");
  }

  function showSuccess(result) {
    var panel = document.getElementById("success-panel");
    if (!panel) return;

    form.hidden = true;
    panel.hidden = false;
    panel.innerHTML =
      '<div class="card" style="text-align:center">' +
      '<span class="card__icon" style="margin-inline:auto;border-color:var(--success);color:var(--success)">' +
      ui.icon("check") +
      "</span>" +
      "<h2>Thank you — your report has been received</h2>" +
      "<p class=\"muted\">It's in the moderation queue now. A person reads every report before it " +
      "appears on the map, so it may be a day or two before you see it." +
      (Store.isDemo
        ? " <strong>You're in demo mode</strong>, so this was saved only in this browser."
        : "") +
      "</p>" +
      '<p class="small muted">Reference: <code>' +
      schema.escapeHtml(result.id) +
      "</code></p>" +
      '<div class="row" style="justify-content:center;margin-top:var(--space-4)">' +
      '<a class="btn btn--primary" href="reports.html">See community reports</a>' +
      '<a class="btn btn--secondary" href="report.html">Submit another</a>' +
      "</div>" +
      '<p class="small muted" style="margin-top:var(--space-5)">' +
      "Please also file this with Loudoun County directly — this site records your experience, " +
      'but it is not a channel the county monitors. <a href="resources.html#official">How to do that</a>.' +
      "</p>" +
      "</div>";

    panel.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function handleSubmit(event) {
    event.preventDefault();

    var button = document.getElementById("submit-button");
    clearAllErrors();
    setFormStatus("");

    // Honeypot: a real person never sees this field, so anything in it is a bot.
    // Pretend to succeed rather than explaining what gave it away.
    var honeypot = document.getElementById("website");
    if (honeypot && honeypot.value) {
      showSuccess({ id: "not-recorded" });
      return;
    }

    var elapsed = (Date.now() - formLoadedAt) / 1000;
    if (elapsed < (config.MIN_SUBMIT_SECONDS || 5)) {
      setFormStatus(
        "That was quicker than we can accept. Take a moment to check your report, then submit again.",
        "error"
      );
      return;
    }

    var draft = collect();
    var check = schema.validateReport(draft);

    if (!check.valid) {
      Object.keys(check.errors).forEach(function (field) {
        showError(field, check.errors[field]);
      });
      setFormStatus("Please fix the highlighted fields.", "error");
      focusFirstError(check.errors);
      return;
    }

    button.disabled = true;
    setFormStatus("Sending your report…");

    Store.submitReport(
      draft,
      selectedFiles.map(function (entry) {
        return entry.file;
      })
    )
      .then(showSuccess)
      .catch(function (error) {
        button.disabled = false;
        setFormStatus(error.message || "Couldn't submit your report. Please try again.", "error");
        console.error(error);
      });
  }

  /* ==================================================================== */
  /* Boot                                                                  */
  /* ==================================================================== */

  function init() {
    ui.fillLocalitySelect(document.getElementById("locality"), "Choose a district…");
    renderCategories();
    renderSeverity();
    renderFacilityStatus();
    initPickMap();
    initPhotos();

    var localitySelect = document.getElementById("locality");
    if (localitySelect) {
      localitySelect.addEventListener("change", function () {
        localitySelect.dataset.autofilled = "false";
        clearError("locality");
      });
    }

    var useLocation = document.getElementById("use-my-location");
    if (useLocation) useLocation.addEventListener("click", useMyLocation);

    var find = document.getElementById("find-address");
    if (find) find.addEventListener("click", findAddress);

    var addressInput = document.getElementById("address-input");
    if (addressInput) {
      addressInput.addEventListener("keydown", function (event) {
        if (event.key === "Enter") {
          event.preventDefault();
          findAddress();
        }
      });
    }

    var description = document.getElementById("description");
    var count = document.getElementById("description-count");
    if (description && count) {
      description.addEventListener("input", function () {
        count.textContent = String(description.value.length);
        if (description.value.trim().length >= schema.LIMITS.descriptionMin) {
          clearError("description");
        }
      });
    }

    form.querySelectorAll('input[name="categories"]').forEach(function (input) {
      input.addEventListener("change", function () {
        clearError("categories");
      });
    });

    form.querySelectorAll('input[name="severity"]').forEach(function (input) {
      input.addEventListener("change", function () {
        clearError("severity");
      });
    });

    var terms = document.getElementById("accepted_terms");
    if (terms) {
      terms.addEventListener("change", function () {
        clearError("accepted_terms");
      });
    }

    form.addEventListener("submit", handleSubmit);
    prefillFromExistingReport(form);
  }

  /* "I'm experiencing this too" on a report's detail view lands here with
     ?like=<report id>. It copies the district and issue categories across so
     the neighbour isn't retyping context — and nothing else. In particular it
     does NOT copy the description or the location: this has to be that
     person's own account of their own address, or the map stops meaning
     anything. It also goes through the normal form and the normal moderation
     queue, like every other submission. */
  function prefillFromExistingReport(form) {
    var id = new URLSearchParams(window.location.search).get("like");
    if (!id || !LDCW.Store) return;

    LDCW.Store.getReport(id)
      .then(function (source) {
        if (!source) return;

        var locality = form.querySelector('[name="locality"]');
        if (locality && source.locality) locality.value = source.locality;

        (source.categories || []).forEach(function (key) {
          var input = form.querySelector('input[name="categories"][value="' + key + '"]');
          if (input) input.checked = true;
        });

        var note = document.getElementById("prefill-note");
        if (note) {
          note.hidden = false;
          note.innerHTML =
            "<strong>Starting from a neighbour's report.</strong> The district and issue types " +
            "are filled in from <a href=\"" +
            "report-detail.html?id=" +
            encodeURIComponent(id) +
            '">the report you came from</a>. Everything else has to be your own account of ' +
            "your own address — change anything that isn't right.";
        }
      })
      .catch(function () {
        /* A bad or stale ?like= is not worth an error message. The form works. */
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})(window.LDCW);
