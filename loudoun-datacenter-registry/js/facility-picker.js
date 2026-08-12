/*
 * "Which facility?" — the picker.
 *
 * This replaced a free-text box, and the reason matters. Typed answers came in
 * as "the big one on Shaw Rd", "Beaumeade?", "not sure", "AWS(?)" — unjoinable
 * to the county records, so a report about a named campus could never be
 * counted alongside the others about the same campus. Choosing from a list
 * fixes that. But the list must never become a wall the reader has to get past
 * to file a report, because plenty of people can hear or smell a facility
 * without knowing which one it is.
 *
 * So:
 *
 *   - "I'm not sure which one" sits at the TOP, always, and is the state the
 *     field starts in. It is a real answer, not an empty one.
 *   - More than one may be chosen. Somebody between two campuses is between
 *     two campuses, and forcing them to pick a favourite loses that.
 *   - Whole districts are selectable too, for "everything around Sterling".
 *   - Anything typed that matches nothing can still be submitted as written,
 *     so the list is never a dead end.
 *
 * It is a real ARIA combobox: the input owns the listbox, options carry
 * aria-selected, the active option is tracked with aria-activedescendant, and
 * everything works from the keyboard. Selections render as removable chips and
 * are mirrored into hidden inputs so the form posts the same shape whether the
 * reader used this, the map, or arrived from a link.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var schema = LDCW.schema;
  var escape = schema.escapeHtml;

  var NOT_SURE = "not-sure";
  var MAX_VISIBLE = 60; // the list is filtered as you type; this bounds the DOM

  var seq = 0;

  function create(root, options) {
    if (!root) return null;
    options = options || {};

    var id = "fp" + ++seq;
    var facilities = [];
    var campusIndex = { list: [], byId: {} };
    var selected = [];        // array of option objects
    var activeIndex = -1;
    var open = false;
    var matches = [];

    /* ---- Option model ----------------------------------------------------
       Three kinds, one shape, so the chips, the listbox and the hidden inputs
       don't each need to know the difference. */

    function notSureOption() {
      return {
        kind: "unsure",
        id: NOT_SURE,
        label: "I'm not sure which one",
        hint: "Perfectly fine — most people don't know. Your district and the pin are enough.",
      };
    }

    function campusOption(campus) {
      return {
        kind: "campus",
        id: campus.id,
        label: campus.name,
        hint: LDCW.campuses.summary(campus),
        campus: campus,
      };
    }

    function districtOption(name, count) {
      return {
        kind: "district",
        id: "district:" + name,
        label: "Anywhere in " + name,
        hint: count + (count === 1 ? " facility" : " facilities") + " in this district",
        district: name,
      };
    }

    function customOption(text) {
      return { kind: "custom", id: "custom:" + text, label: text, hint: "As you typed it" };
    }

    function allOptions() {
      var out = [notSureOption()];

      var counts = {};
      facilities.forEach(function (facility) {
        if (!facility.district) return;
        counts[facility.district] = (counts[facility.district] || 0) + 1;
      });
      Object.keys(counts)
        .sort()
        .forEach(function (name) {
          out.push(districtOption(name, counts[name]));
        });

      campusIndex.list.forEach(function (campus) {
        out.push(campusOption(campus));
      });

      return out;
    }

    /* ---- DOM ------------------------------------------------------------- */

    root.classList.add("fpicker");
    root.innerHTML =
      '<div class="fpicker__control">' +
      '<ul class="fpicker__chips" id="' + id + '-chips"></ul>' +
      '<input class="fpicker__input" type="text" role="combobox" autocomplete="off" ' +
      'aria-expanded="false" aria-autocomplete="list" aria-controls="' + id + '-list" ' +
      'id="' + (options.inputId || id + "-input") + '" ' +
      'placeholder="' + escape(options.placeholder || "Search campuses, or pick a district…") + '">' +
      '<button class="fpicker__toggle" type="button" tabindex="-1" aria-hidden="true">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
      'stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>' +
      "</button></div>" +
      '<ul class="fpicker__list" id="' + id + '-list" role="listbox" ' +
      'aria-label="Facilities and districts" hidden></ul>' +
      '<p class="fpicker__status" role="status" aria-live="polite"></p>';

    var control = root.querySelector(".fpicker__control");
    var chips = root.querySelector(".fpicker__chips");
    var input = root.querySelector(".fpicker__input");
    var toggle = root.querySelector(".fpicker__toggle");
    var list = root.querySelector(".fpicker__list");
    var status = root.querySelector(".fpicker__status");

    /* ---- Rendering -------------------------------------------------------- */

    function renderChips() {
      chips.innerHTML = selected
        .map(function (option, i) {
          return (
            '<li class="fpicker__chip fpicker__chip--' + option.kind + '">' +
            "<span>" + escape(option.label) + "</span>" +
            '<button type="button" class="fpicker__remove" data-remove="' + i + '" ' +
            'aria-label="Remove ' + escape(option.label) + '">' +
            '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" ' +
            'stroke-linecap="round" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg>' +
            "</button></li>"
          );
        })
        .join("");

      chips.querySelectorAll("[data-remove]").forEach(function (button) {
        button.addEventListener("click", function () {
          remove(Number(button.getAttribute("data-remove")));
          input.focus();
        });
      });

      // With something chosen the placeholder would be a lie about what the
      // field currently holds.
      input.placeholder = selected.length
        ? "Add another…"
        : options.placeholder || "Search campuses, or pick a district…";

      root.classList.toggle("is-filled", selected.length > 0);
    }

    function isSelected(option) {
      return selected.some(function (chosen) {
        return chosen.id === option.id;
      });
    }

    function renderList() {
      var query = input.value.trim().toLowerCase();

      matches = allOptions().filter(function (option) {
        // "I'm not sure" stays reachable however hard you filter — it is the
        // escape hatch, and hiding it when someone types a name they got wrong
        // is exactly backwards.
        if (option.kind === "unsure") return true;
        if (!query) return true;
        var haystack = (
          option.label +
          " " +
          (option.hint || "") +
          " " +
          (option.campus ? option.campus.operators.join(" ") : "")
        ).toLowerCase();
        return haystack.indexOf(query) !== -1;
      });

      var truncated = matches.length > MAX_VISIBLE;
      var shown = matches.slice(0, MAX_VISIBLE);

      // Nothing matched but "not sure": offer what they typed, verbatim.
      if (query && shown.length === 1 && !options.disallowCustom) {
        var custom = customOption(input.value.trim());
        shown.push(custom);
        matches = shown;
      }

      list.innerHTML =
        shown
          .map(function (option, i) {
            return (
              '<li class="fpicker__option fpicker__option--' + option.kind + '" role="option" ' +
              'id="' + id + "-opt" + i + '" ' +
              'aria-selected="' + (isSelected(option) ? "true" : "false") + '" ' +
              'data-index="' + i + '">' +
              '<span class="fpicker__option-label">' + escape(option.label) + "</span>" +
              (option.hint
                ? '<span class="fpicker__option-hint">' + escape(option.hint) + "</span>"
                : "") +
              "</li>"
            );
          })
          .join("") +
        (truncated
          ? '<li class="fpicker__more">' +
            (matches.length - MAX_VISIBLE) +
            " more — keep typing to narrow it down</li>"
          : "");

      list.querySelectorAll("[data-index]").forEach(function (node) {
        // mousedown, not click: click fires after the input's blur, by which
        // point the list has already closed and the option is gone.
        node.addEventListener("mousedown", function (event) {
          event.preventDefault();
          choose(Number(node.getAttribute("data-index")));
        });
      });

      if (activeIndex >= shown.length) activeIndex = shown.length - 1;
      paintActive();
    }

    function paintActive() {
      var nodes = list.querySelectorAll("[data-index]");
      nodes.forEach(function (node, i) {
        node.classList.toggle("is-active", i === activeIndex);
      });
      if (activeIndex >= 0 && nodes[activeIndex]) {
        input.setAttribute("aria-activedescendant", nodes[activeIndex].id);
        // Keyboard navigation has to bring the option into view itself; the
        // list scrolls independently of the page.
        var node = nodes[activeIndex];
        var top = node.offsetTop;
        var bottom = top + node.offsetHeight;
        if (top < list.scrollTop) list.scrollTop = top;
        else if (bottom > list.scrollTop + list.clientHeight) {
          list.scrollTop = bottom - list.clientHeight;
        }
      } else {
        input.removeAttribute("aria-activedescendant");
      }
    }

    function say() {
      if (!selected.length) {
        status.textContent = "";
        return;
      }
      if (selected.length === 1 && selected[0].kind === "unsure") {
        status.textContent = "That's fine — your district and the map pin are enough.";
        return;
      }
      var parcels = selected.reduce(function (sum, option) {
        return sum + (option.campus ? option.campus.parcels.length : 0);
      }, 0);
      status.textContent =
        selected.length +
        (selected.length === 1 ? " selection" : " selections") +
        (parcels ? " · " + parcels + (parcels === 1 ? " county parcel" : " county parcels") : "");
    }

    /* ---- Selection -------------------------------------------------------- */

    function add(option) {
      if (!option) return;

      if (option.kind === "unsure") {
        // "Not sure" is exclusive in both directions: it cannot sit beside a
        // named campus without contradicting it.
        selected = [option];
      } else {
        selected = selected.filter(function (chosen) {
          return chosen.kind !== "unsure";
        });
        if (!isSelected(option)) selected.push(option);
      }

      commit();
    }

    function remove(index) {
      selected.splice(index, 1);
      commit();
    }

    function commit() {
      renderChips();
      say();
      writeHidden();
      renderList();
      if (typeof options.onChange === "function") options.onChange(value());
    }

    /* ---- Value ------------------------------------------------------------
       Mirrored into hidden inputs so a form submits the same shape no matter
       how the selection was made, and so the value survives a page that never
       runs this file's JavaScript at all. */

    function writeHidden() {
      var v = value();
      setHidden("facility_ids", v.ids.join(","));
      setHidden("facility_name", v.name);
      setHidden("facility_districts", v.districts.join(","));
    }

    function setHidden(name, text) {
      if (!options.form) return;
      var node = options.form.querySelector('input[type="hidden"][name="' + name + '"]');
      if (!node) {
        node = document.createElement("input");
        node.type = "hidden";
        node.name = name;
        options.form.appendChild(node);
      }
      node.value = text;
    }

    function value() {
      var unsure = selected.length === 1 && selected[0].kind === "unsure";

      var districts = [];
      selected.forEach(function (option) {
        if (option.kind === "district" && districts.indexOf(option.district) === -1) {
          districts.push(option.district);
        }
        if (option.campus) {
          option.campus.districts.forEach(function (name) {
            if (districts.indexOf(name) === -1) districts.push(name);
          });
        }
      });

      var statuses = selected
        .filter(function (option) {
          return option.campus;
        })
        .map(function (option) {
          return option.campus.status;
        });

      return {
        unsure: unsure,
        ids: unsure ? [] : selected.map(function (option) { return option.id; }),
        // A single human-readable string, because that is what the existing
        // reports table stores and what a moderator reads.
        name: unsure
          ? ""
          : selected
              .map(function (option) {
                return option.label;
              })
              .join(", "),
        districts: districts,
        // Only offer a build stage when every campus chosen agrees on one.
        status: statuses.length && statuses.every(function (s) { return s === statuses[0]; })
          ? statuses[0]
          : null,
        operators: selected
          .filter(function (option) { return option.campus && option.campus.operator; })
          .map(function (option) { return option.campus.operator; }),
        campuses: selected
          .filter(function (option) { return option.campus; })
          .map(function (option) { return option.campus; }),
        options: selected.slice(),
      };
    }

    /* ---- Open / close ----------------------------------------------------- */

    function openList() {
      if (open) return;
      open = true;
      list.hidden = false;
      input.setAttribute("aria-expanded", "true");
      renderList();
    }

    function closeList() {
      if (!open) return;
      open = false;
      list.hidden = true;
      input.setAttribute("aria-expanded", "false");
      input.removeAttribute("aria-activedescendant");
      activeIndex = -1;
    }

    function choose(index) {
      var option = matches[index];
      if (!option) return;
      if (isSelected(option)) {
        var at = -1;
        selected.forEach(function (chosen, i) {
          if (chosen.id === option.id) at = i;
        });
        if (at !== -1) remove(at);
      } else {
        add(option);
      }
      input.value = "";
      renderList();
      input.focus();
    }

    /* ---- Events ----------------------------------------------------------- */

    input.addEventListener("focus", openList);
    input.addEventListener("input", function () {
      activeIndex = 0;
      openList();
      renderList();
    });

    control.addEventListener("mousedown", function (event) {
      if (event.target === control || event.target === chips) {
        event.preventDefault();
        input.focus();
      }
    });

    toggle.addEventListener("mousedown", function (event) {
      event.preventDefault();
      if (open) closeList();
      else {
        input.focus();
        openList();
      }
    });

    input.addEventListener("keydown", function (event) {
      if (event.key === "ArrowDown") {
        event.preventDefault();
        openList();
        activeIndex = Math.min(activeIndex + 1, matches.length - 1);
        paintActive();
      } else if (event.key === "ArrowUp") {
        event.preventDefault();
        activeIndex = Math.max(activeIndex - 1, 0);
        paintActive();
      } else if (event.key === "Enter") {
        if (open && activeIndex >= 0) {
          // Only swallow the Enter when it is actually choosing something —
          // otherwise it would silently stop the form from submitting.
          event.preventDefault();
          choose(activeIndex);
        }
      } else if (event.key === "Escape") {
        if (open) {
          event.preventDefault();
          closeList();
        }
      } else if (event.key === "Backspace" && !input.value && selected.length) {
        remove(selected.length - 1);
      }
    });

    document.addEventListener("mousedown", function (event) {
      if (!root.contains(event.target)) closeList();
    });

    input.addEventListener("blur", function () {
      // A pointer press inside the list moves focus for an instant; closing on
      // that would cancel the very choice being made.
      setTimeout(function () {
        if (!root.contains(document.activeElement)) closeList();
      }, 0);
    });

    /* ---- Public ----------------------------------------------------------- */

    var api = {
      setFacilities: function (rows) {
        facilities = rows || [];
        campusIndex = LDCW.campuses.index(facilities);
        renderList();
        return api;
      },

      /* Select by campus id, "district:Name", or NOT_SURE. Used by the map
         hand-off and by links carrying a selection. Unknown ids are dropped
         rather than added as free text — they came from a machine, not a
         person, so a typo is a bug and should not become a chip. */
      selectIds: function (ids, opts) {
        var wanted = (ids || []).filter(Boolean);
        if (!(opts && opts.append)) selected = [];

        wanted.forEach(function (wantedId) {
          if (wantedId === NOT_SURE) return add(notSureOption());
          if (wantedId.indexOf("district:") === 0) {
            var name = wantedId.slice("district:".length);
            var count = facilities.filter(function (f) {
              return f.district === name;
            }).length;
            if (count) add(districtOption(name, count));
            return;
          }
          var campus = campusIndex.byId[wantedId];
          if (campus) add(campusOption(campus));
        });

        commit();
        return api;
      },

      /* Select whichever campus a county parcel belongs to. This is what the
         map calls when a marker is tapped. */
      selectParcel: function (parcel, opts) {
        var campus = LDCW.campuses.forParcel(facilities, parcel);
        if (!campus) return api;
        add(campusOption(campus));
        if (opts && opts.silent !== true) {
          input.value = "";
          renderList();
        }
        return api;
      },

      selectNotSure: function () {
        add(notSureOption());
        return api;
      },

      clear: function () {
        selected = [];
        commit();
        return api;
      },

      value: value,
      element: root,
      input: input,
      NOT_SURE: NOT_SURE,
    };

    renderChips();
    writeHidden();

    return api;
  }

  LDCW.facilityPicker = { create: create, NOT_SURE: NOT_SURE };
})(window.LDCW);
