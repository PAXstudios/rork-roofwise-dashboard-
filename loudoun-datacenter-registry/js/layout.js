/*
 * Shared site chrome.
 *
 * There is no build step here, so the header and footer are injected at runtime
 * instead of being duplicated across ten HTML files. Each page ships a
 * <header id="site-header"> and <footer id="site-footer"> placeholder plus a
 * <noscript> copy of the nav links so the site still navigates without JS.
 *
 * The brand mark is the outline of Loudoun County, generated from the county's
 * own district boundaries by scripts/build-county-svg.py. It is inlined rather
 * than loaded as an <img> so it inherits currentColor and can be animated.
 */

(function () {
  "use strict";

  var NAV = [
    { href: "index.html", label: "Map" },
    { href: "reports.html", label: "Reports" },
    { href: "watchlist.html", label: "Watchlist" },
    { href: "news.html", label: "News" },
    { href: "stats.html", label: "Statistics" },
    { href: "resources.html", label: "Resources" },
    { href: "about.html", label: "About" },
  ];

  var FOOTER_LINKS = [
    {
      title: "The project",
      links: [
        { href: "index.html", label: "Map" },
        { href: "report.html", label: "Report an issue" },
        { href: "reports.html", label: "Community reports" },
        { href: "watchlist.html", label: "Watchlist" },
        { href: "stats.html", label: "Statistics" },
      ],
    },
    {
      title: "Information",
      links: [
        { href: "news.html", label: "In the news" },
        { href: "resources.html", label: "Resources & FAQ" },
        { href: "about.html", label: "About this project" },
        { href: "privacy.html", label: "Privacy policy" },
        { href: "terms.html", label: "Terms of use" },
      ],
    },
  ];

  /* The county silhouette, fetched once and cached for the header, the footer
     and any watermark on the page. */
  var markPromise = null;

  function loadMark() {
    if (markPromise) return markPromise;
    markPromise = fetch("assets/loudoun-mark.svg")
      .then(function (response) {
        if (!response.ok) throw new Error("mark unavailable");
        return response.text();
      })
      .catch(function () {
        return "";
      });
    return markPromise;
  }

  /* ---- Helpers --------------------------------------------------------- */

  function currentPage() {
    var path = window.location.pathname;
    var file = path.substring(path.lastIndexOf("/") + 1);
    return file === "" ? "index.html" : file;
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  /* ---- Markup ---------------------------------------------------------- */

  function headerMarkup(page) {
    var items = NAV.map(function (item) {
      var isCurrent = item.href === page;
      return (
        '<li><a class="site-nav__link" href="' +
        item.href +
        '"' +
        (isCurrent ? ' aria-current="page"' : "") +
        ">" +
        escapeHtml(item.label) +
        "</a></li>"
      );
    }).join("");

    return (
      '<div class="container site-header__inner">' +
      '<a class="brand" href="index.html">' +
      '<span class="brand__mark" data-county-mark aria-hidden="true"></span>' +
      '<span class="brand__name">Loudoun Data Center Watch</span>' +
      '<span class="brand__name--short">LDC Watch</span>' +
      "</a>" +
      '<button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-nav">' +
      "Menu</button>" +
      '<nav class="site-nav" id="site-nav" aria-label="Main">' +
      '<ul class="site-nav__list">' +
      items +
      "</ul></nav>" +
      '<div class="header-actions">' +
      '<a class="btn btn--primary btn--sm header-cta" href="report.html">Report an issue</a>' +
      "</div>" +
      "</div>"
    );
  }

  function footerMarkup() {
    var columns = FOOTER_LINKS.map(function (group) {
      var links = group.links
        .map(function (item) {
          return '<li><a href="' + item.href + '">' + escapeHtml(item.label) + "</a></li>";
        })
        .join("");
      return "<div><h2>" + escapeHtml(group.title) + "</h2><ul>" + links + "</ul></div>";
    }).join("");

    return (
      '<div class="container">' +
      '<div class="site-footer__grid">' +
      "<div>" +
      "<h2>Loudoun Data Center Watch</h2>" +
      '<p class="muted">A community record of how data center development is affecting the people who live next to it — built so scattered complaints become something you can point at.</p>' +
      '<p><a class="btn btn--primary btn--sm" href="report.html">Report an issue</a></p>' +
      "</div>" +
      columns +
      "</div>" +
      '<div class="site-footer__disclaimer">' +
      "<p><strong>This is an independent community project.</strong> It is not affiliated with, endorsed by, or operated by Loudoun County government, Erin Brockovich, or any data center owner or operator. " +
      "Community reports are unverified first-hand accounts submitted by residents. They are not findings of fact, and they do not establish that any named company caused any condition described.</p>" +
      '<p>Facility data © Loudoun County GIS. Basemap © <a href="https://www.openstreetmap.org/copyright" rel="noopener">OpenStreetMap</a> contributors. ' +
      'See <a href="about.html">About</a> for full sources and <a href="privacy.html">Privacy</a> for how submissions are handled.</p>' +
      "</div>" +
      "</div>"
    );
  }

  /* ---- Mount ------------------------------------------------------------ */

  function mount() {
    var page = currentPage();

    var header = document.getElementById("site-header");
    if (header) {
      header.className = "site-header";
      header.innerHTML = headerMarkup(page);

      var toggle = header.querySelector(".nav-toggle");
      var nav = header.querySelector(".site-nav");
      if (toggle && nav) {
        toggle.addEventListener("click", function () {
          var open = nav.classList.toggle("is-open");
          toggle.setAttribute("aria-expanded", String(open));
        });
        // Collapse the mobile menu when moving to the desktop layout so the
        // is-open class can't leave the nav in a half-styled state.
        window.addEventListener("resize", function () {
          if (window.innerWidth >= 960) {
            nav.classList.remove("is-open");
            toggle.setAttribute("aria-expanded", "false");
          }
        });
      }
    }

    var footer = document.getElementById("site-footer");
    if (footer) {
      footer.className = "site-footer";
      footer.innerHTML = footerMarkup();
    }

    // Fill every county-mark slot on the page — the header brand and any
    // watermarks a page has declared.
    loadMark().then(function (svg) {
      if (!svg) return;
      document.querySelectorAll("[data-county-mark]").forEach(function (slot) {
        slot.innerHTML = svg;
      });
    });

    if (window.LDCW && window.LDCW.motion) {
      window.LDCW.motion.stickyHeader(".site-header");
      window.LDCW.motion.readingProgress();
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mount);
  } else {
    mount();
  }
})();
