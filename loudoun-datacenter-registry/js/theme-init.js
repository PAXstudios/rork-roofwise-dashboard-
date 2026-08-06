/*
 * Applies the saved theme before first paint.
 *
 * This is deliberately a separate, render-blocking script in <head> rather than
 * part of layout.js: if it ran after parsing, the page would flash light before
 * switching to dark. It is tiny on purpose.
 */
(function () {
  try {
    var saved = localStorage.getItem("ldcw:theme");
    if (saved === "dark" || saved === "light") {
      document.documentElement.setAttribute("data-theme", saved);
    }
  } catch (err) {
    /* Private mode or storage disabled — fall back to the OS preference. */
  }
})();
