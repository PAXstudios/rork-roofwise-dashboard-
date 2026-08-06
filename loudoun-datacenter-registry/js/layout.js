/*
 * Shared site chrome.
 *
 * There is no build step here, so the header and footer are injected at runtime
 * instead of being duplicated across ten HTML files. Each page ships a
 * <header id="site-header"> and <footer id="site-footer"> placeholder plus a
 * <noscript> copy of the nav links so the site still navigates without JS.
 */

(function () {
  "use strict";

  var NAV = [
    { href: "index.html", label: "Map" },
    { href: "reports.html", label: "Reports" },
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
        { href: "stats.html", label: "Statistics" },
      ],
    },
    {
      title: "Information",
      links: [
        { href: "resources.html", label: "Resources & FAQ" },
        { href: "about.html", label: "About this project" },
        { href: "privacy.html", label: "Privacy policy" },
        { href: "terms.html", label: "Terms of use" },
      ],
    },
  ];

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

  /* ---- Theme ----------------------------------------------------------- */

  function resolvedTheme() {
    var explicit = document.documentElement.getAttribute("data-theme");
    if (explicit) return explicit;
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  }

  function toggleTheme() {
    var next = resolvedTheme() === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    try {
      localStorage.setItem("ldcw:theme", next);
    } catch (err) {
      /* Storage unavailable — the choice just won't persist. */
    }
    var button = document.querySelector(".theme-toggle");
    if (button) {
      button.setAttribute(
        "aria-label",
        next === "dark" ? "Switch to light theme" : "Switch to dark theme"
      );
    }
    // Let the map know it should restyle its tiles.
    window.dispatchEvent(new CustomEvent("ldcw:themechange", { detail: { theme: next } }));
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
      '<svg class="brand__mark" viewBox="0 0 32 32" aria-hidden="true" focusable="false">' +
      '<rect x="3" y="7" width="26" height="6" rx="1.5" fill="none" stroke="currentColor" stroke-width="2"/>' +
      '<rect x="3" y="17" width="26" height="6" rx="1.5" fill="none" stroke="currentColor" stroke-width="2"/>' +
      '<circle cx="8" cy="10" r="1.4" fill="var(--status-reported)"/>' +
      '<circle cx="8" cy="20" r="1.4" fill="var(--status-reported)"/>' +
      '<path d="M20 10h5M20 20h5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>' +
      "</svg>" +
      '<span class="brand__name">Loudoun Data Center Watch</span>' +
      '<span class="brand__name--short">LDC Watch</span>' +
      "</a>" +
      '<button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-nav">' +
      '<svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true" focusable="false">' +
      '<path d="M3 5h14M3 10h14M3 15h14" stroke="currentColor" stroke-width="2" stroke-linecap="round" fill="none"/>' +
      "</svg>Menu</button>" +
      '<nav class="site-nav" id="site-nav" aria-label="Main">' +
      '<ul class="site-nav__list">' +
      items +
      "</ul></nav>" +
      '<div class="header-actions">' +
      '<button class="theme-toggle" type="button" aria-label="Switch theme">' +
      '<svg class="theme-toggle__sun" viewBox="0 0 20 20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8">' +
      '<circle cx="10" cy="10" r="3.5"/><path d="M10 1.5v2M10 16.5v2M18.5 10h-2M3.5 10h-2M16 4l-1.4 1.4M5.4 14.6 4 16M16 16l-1.4-1.4M5.4 5.4 4 4" stroke-linecap="round"/>' +
      "</svg>" +
      '<svg class="theme-toggle__moon" viewBox="0 0 20 20" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" stroke-width="1.8">' +
      '<path d="M16.5 12.4A7 7 0 0 1 7.6 3.5a7 7 0 1 0 8.9 8.9Z" stroke-linejoin="round"/>' +
      "</svg></button>" +
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
      '<h2>Loudoun Data Center Watch</h2>' +
      '<p class="muted">A community record of how data center development is affecting the people who live next to it — built so scattered complaints become something you can point at.</p>' +
      '<p><a class="btn btn--primary btn--sm" href="report.html">Report an issue</a></p>' +
      "</div>" +
      columns +
      "</div>" +
      '<div class="site-footer__disclaimer">' +
      "<p><strong>This is an independent community project.</strong> It is not affiliated with, endorsed by, or operated by Loudoun County government, Erin Brockovich, or any data center owner or operator. " +
      "Community reports are unverified first-hand accounts submitted by residents. They are not findings of fact, and they do not establish that any named company caused any condition described.</p>" +
      "<p>Facility data © Loudoun County GIS. Basemap © <a href=\"https://www.openstreetmap.org/copyright\" rel=\"noopener\">OpenStreetMap</a> contributors. " +
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

      var themeButton = header.querySelector(".theme-toggle");
      if (themeButton) {
        themeButton.setAttribute(
          "aria-label",
          resolvedTheme() === "dark" ? "Switch to light theme" : "Switch to dark theme"
        );
        themeButton.addEventListener("click", toggleTheme);
      }
    }

    var footer = document.getElementById("site-footer");
    if (footer) {
      footer.className = "site-footer";
      footer.innerHTML = footerMarkup();
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mount);
  } else {
    mount();
  }
})();
