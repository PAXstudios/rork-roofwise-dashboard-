/*
 * Local news coverage.
 *
 * Reads data/news.json, written out of band by scripts/refresh-news.py. The
 * fetch has to happen there rather than here because not one of the feeds
 * involved sends CORS headers — Google News, Virginia Mercury, Cardinal News,
 * WTOP, the county calendar. A browser request to any of them fails, and the
 * restriction is on the far end so there is no request shape that works.
 *
 * Headline, publication, date and link. Deliberately nothing else. We have not
 * read these articles, only their headlines, so summarising them — by hand or
 * with a model — would be inventing. Linking out is also the copyright-safe
 * pattern, and it sends traffic to the newsrooms doing the reporting, which a
 * site like this depends on continuing to exist.
 */

(function (LDCW) {
  "use strict";

  var schema = LDCW.schema;
  var escape = schema.escapeHtml;

  var state = { items: [], topics: {}, topic: "", search: "", limit: 40, generated: null };

  function itemMarkup(item) {
    return (
      '<li class="news-item">' +
      '<a class="news-item__link" href="' +
      escape(item.url) +
      '" target="_blank" rel="noopener noreferrer nofollow">' +
      escape(item.title) +
      "</a>" +
      '<p class="news-item__meta">' +
      '<span class="news-item__source">' +
      escape(item.source) +
      "</span>" +
      '<span class="news-item__date"><time datetime="' +
      escape(item.published_at) +
      '">' +
      escape(schema.formatDate(item.published_at)) +
      "</time> · " +
      escape(schema.formatRelative(item.published_at)) +
      "</span>" +
      (state.topics[item.topic]
        ? '<span class="news-item__topic">' + escape(state.topics[item.topic]) + "</span>"
        : "") +
      "</p>" +
      "</li>"
    );
  }

  function visible() {
    var needle = state.search.trim().toLowerCase();
    return state.items.filter(function (item) {
      if (state.topic && item.topic !== state.topic) return false;
      if (!needle) return true;
      return (
        item.title.toLowerCase().indexOf(needle) !== -1 ||
        item.source.toLowerCase().indexOf(needle) !== -1
      );
    });
  }

  function render() {
    var list = document.getElementById("news-list");
    var count = document.getElementById("news-count");
    if (!list) return;

    var matches = visible();
    var shown = matches.slice(0, state.limit);

    if (count) {
      count.textContent =
        matches.length === state.items.length
          ? schema.formatNumber(matches.length) + " headlines"
          : "Showing " +
            schema.formatNumber(matches.length) +
            " of " +
            schema.formatNumber(state.items.length) +
            " headlines";
    }

    if (!matches.length) {
      list.innerHTML =
        '<div class="empty-state"><p class="empty-state__title">Nothing matches</p>' +
        "<p>Try a different topic or search term.</p></div>";
      return;
    }

    list.innerHTML = '<ul class="news-list">' + shown.map(itemMarkup).join("") + "</ul>";

    var more = document.getElementById("news-more");
    if (more) {
      more.hidden = shown.length >= matches.length;
      more.textContent =
        "Show " +
        Math.min(40, matches.length - shown.length) +
        " more of " +
        schema.formatNumber(matches.length - shown.length) +
        " remaining";
    }
  }

  function renderFilters() {
    var host = document.getElementById("news-filters");
    if (!host) return;

    var counts = {};
    state.items.forEach(function (item) {
      counts[item.topic] = (counts[item.topic] || 0) + 1;
    });

    var keys = Object.keys(state.topics).filter(function (key) {
      return counts[key];
    });

    host.innerHTML =
      '<button type="button" class="chip is-active" data-topic="">All (' +
      schema.formatNumber(state.items.length) +
      ")</button>" +
      keys
        .map(function (key) {
          return (
            '<button type="button" class="chip" data-topic="' +
            escape(key) +
            '">' +
            escape(state.topics[key]) +
            " (" +
            schema.formatNumber(counts[key]) +
            ")</button>"
          );
        })
        .join("");

    host.querySelectorAll("[data-topic]").forEach(function (button) {
      button.addEventListener("click", function () {
        state.topic = button.getAttribute("data-topic");
        state.limit = 40;
        host.querySelectorAll("[data-topic]").forEach(function (other) {
          other.classList.toggle("is-active", other === button);
        });
        render();
      });
    });
  }

  function mountPage() {
    var list = document.getElementById("news-list");
    if (!list) return;

    LDCW.ui.showLoading(list, "Loading headlines…");

    LDCW.Store.loadJson("data/news.json")
      .then(function (data) {
        state.items = data.items || [];
        state.topics = data.topics || {};
        state.generated = data.generated_at;

        var stamp = document.getElementById("news-generated");
        if (stamp && data.generated_at) {
          stamp.textContent =
            "Headlines last collected " + schema.formatRelative(data.generated_at) + ".";
        }

        renderFilters();
        render();

        var search = document.getElementById("news-search");
        if (search) {
          search.addEventListener(
            "input",
            LDCW.ui.debounce(function () {
              state.search = search.value;
              state.limit = 40;
              render();
            }, 200)
          );
        }

        var more = document.getElementById("news-more");
        if (more) {
          more.addEventListener("click", function () {
            state.limit += 40;
            render();
          });
        }
      })
      .catch(function () {
        // A missing or stale news file is not an error worth a red banner. The
        // rest of the site is unaffected and the reader can do something else.
        list.innerHTML =
          '<div class="empty-state"><p class="empty-state__title">No headlines loaded</p>' +
          "<p>The news file has not been generated yet. Run " +
          "<code>python3 scripts/refresh-news.py</code>, or check back later.</p></div>";
      });
  }

  /* ---- Home page ---------------------------------------------------------
     Reads the small file, not the archive. The archive is a couple of hundred
     kilobytes and this shows five lines. */

  function mountHome() {
    var host = document.getElementById("home-news");
    if (!host) return;

    LDCW.Store.loadJson("data/news-home.json")
      .then(function (data) {
        var items = (data.items || []).slice(0, 5);
        if (!items.length) {
          host.closest("section").hidden = true;
          return;
        }
        host.innerHTML = '<ul class="news-list news-list--compact">' +
          items.map(itemMarkup).join("") + "</ul>";
      })
      .catch(function () {
        // Hide the whole section rather than leaving a heading over a hole.
        var section = host.closest("section");
        if (section) section.hidden = true;
      });
  }

  LDCW.news = { mountPage: mountPage, mountHome: mountHome };

  function boot() {
    mountPage();
    mountHome();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})(window.LDCW);
