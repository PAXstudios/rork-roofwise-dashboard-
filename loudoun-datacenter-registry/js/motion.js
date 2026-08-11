/*
 * Shared motion utilities.
 *
 * Every entry point checks prefersReducedMotion() first and short-circuits to
 * the finished state. That matters more than usual here: the CSS in
 * animations.css uses `both` fill mode in several places, so an element left
 * mid-sequence would be stuck invisible rather than merely un-animated.
 *
 * The .reveal class is applied by THIS FILE, never in the HTML. A visitor with
 * scripting disabled therefore sees a complete, static page instead of a blank
 * one waiting for an observer that will never fire.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var reduceQuery =
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)");

  function prefersReducedMotion() {
    return Boolean(reduceQuery && reduceQuery.matches);
  }

  /* ---- Scroll reveal ------------------------------------------------------
     Deliberately a scroll + getBoundingClientRect check rather than an
     IntersectionObserver.

     IO looks like the right tool, but its callback is asynchronous and can be
     coalesced away during a fast scroll. When that happens the element keeps
     the opacity:0 that .reveal applied and is stranded invisible forever —
     content silently lost, which is far worse than an animation not playing.
     A synchronous rect check on a throttled scroll cannot miss, and the cost
     for the ~30 elements involved is negligible.

     There is also a hard failsafe: anything still pending after
     FAILSAFE_MS is revealed regardless. */

  var pending = [];
  var listening = false;
  var FAILSAFE_MS = 4000;

  function flush() {
    if (!pending.length) return;

    var viewport = window.innerHeight || document.documentElement.clientHeight;
    var remaining = [];

    pending.forEach(function (entry) {
      var rect = entry.node.getBoundingClientRect();
      // Trigger once any part of the element is within the viewport, plus a
      // small lead-in so the animation is underway as the eye arrives.
      if (rect.top < viewport * 0.94 && rect.bottom > 0) {
        entry.run();
      } else {
        remaining.push(entry);
      }
    });

    pending = remaining;
  }

  function revealAll() {
    var queued = pending;
    pending = [];
    queued.forEach(function (entry) {
      entry.run();
    });
  }

  /** Run `callback` once `node` is scrolled into view (or on the failsafe). */
  function whenVisible(node, callback) {
    if (!node) return;
    pending.push({ node: node, run: callback });
    listen();
    flush();
  }

  function listen() {
    if (listening) return;
    listening = true;

    var ticking = false;
    function onScroll() {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(function () {
        ticking = false;
        flush();
      });
    }

    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });
    // Printing must never produce a page of blank sections.
    window.addEventListener("beforeprint", revealAll);
    window.setTimeout(revealAll, FAILSAFE_MS);
  }

  /**
   * Mark elements to animate in as they scroll into view.
   *
   * @param {string} selector
   * @param {object} [options]
   *   - group {boolean}  cascade the element's children instead of the element
   *   - stagger {boolean} number the elements so they arrive in sequence
   */
  function reveal(selector, options) {
    options = options || {};
    var nodes = Array.prototype.slice.call(document.querySelectorAll(selector));
    if (!nodes.length) return;

    // With reduced motion nothing is hidden in the first place, so there is
    // nothing to reveal — no class is added and the CSS never applies.
    if (prefersReducedMotion()) return;

    nodes.forEach(function (node, index) {
      node.classList.add(options.group ? "reveal-group" : "reveal");

      if (options.stagger !== false) {
        var children = options.group ? node.children : [node];
        Array.prototype.forEach.call(children, function (child, childIndex) {
          child.style.setProperty(
            "--stagger-index",
            String(options.group ? childIndex : index)
          );
        });
      }

      pending.push({
        node: node,
        run: function () {
          node.classList.add("is-visible");
        },
      });
    });

    listen();
    // Resolve anything already on screen before the first scroll event.
    flush();
  }

  /** Reveal an element immediately, skipping the observer. */
  function show(node) {
    if (node) node.classList.add("is-visible");
  }

  /* ---- Count-up ---------------------------------------------------------- */

  function easeOutCubic(t) {
    return 1 - Math.pow(1 - t, 3);
  }

  /**
   * Animate a number from 0 to `value`. Falls back to setting the final text
   * under reduced motion, and never leaves a partial number on screen.
   */
  function countUp(node, value, options) {
    if (!node) return;
    options = options || {};

    var target = Number(value);
    if (!isFinite(target)) {
      node.textContent = String(value);
      return;
    }

    var format =
      options.format ||
      function (n) {
        return Math.round(n).toLocaleString("en-US");
      };

    if (prefersReducedMotion() || target === 0) {
      node.textContent = format(target);
      return;
    }

    var duration = options.duration || 1100;
    var started = null;

    function frame(now) {
      if (started === null) started = now;
      var progress = Math.min((now - started) / duration, 1);
      node.textContent = format(target * easeOutCubic(progress));
      if (progress < 1) {
        window.requestAnimationFrame(frame);
      } else {
        node.textContent = format(target);
      }
    }

    window.requestAnimationFrame(frame);
  }

  /** Count up once the element scrolls into view. */
  function countUpOnView(node, value, options) {
    if (!node) return;

    if (prefersReducedMotion()) {
      countUp(node, value, options);
      return;
    }

    // Same queue as reveal(), so a stat tile can never be left showing the "—"
    // placeholder because a callback was missed.
    whenVisible(node, function () {
      countUp(node, value, options);
    });
  }

  /* ---- Parallax ----------------------------------------------------------- */

  /**
   * Drift an element vertically as it passes through the viewport. Writes to a
   * custom property rather than to `transform` directly, so the CSS keeps
   * ownership of how the offset is applied.
   */
  function parallax(selector, strength) {
    if (prefersReducedMotion()) return;

    var nodes = Array.prototype.slice.call(document.querySelectorAll(selector));
    if (!nodes.length) return;

    var amount = strength || 0.12;
    var ticking = false;

    function update() {
      ticking = false;
      var viewport = window.innerHeight;

      nodes.forEach(function (node) {
        var rect = node.getBoundingClientRect();
        if (rect.bottom < 0 || rect.top > viewport) return;
        // -1 at the bottom of the viewport, +1 at the top.
        var progress = (viewport / 2 - (rect.top + rect.height / 2)) / viewport;
        node.style.setProperty("--parallax", (progress * 100 * amount).toFixed(1) + "px");
      });
    }

    function onScroll() {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(update);
    }

    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });
    update();
  }

  /* ---- Sticky header ------------------------------------------------------ */

  function stickyHeader(selector) {
    var header = document.querySelector(selector || ".site-header");
    if (!header) return;

    var ticking = false;

    function update() {
      ticking = false;
      header.classList.toggle("is-stuck", window.scrollY > 8);
    }

    window.addEventListener(
      "scroll",
      function () {
        if (ticking) return;
        ticking = true;
        window.requestAnimationFrame(update);
      },
      { passive: true }
    );

    update();
  }

  /* ---- Reading progress ---------------------------------------------------
     A hairline across the top showing how far through the page you are.

     Deliberately driven by a transform on a fixed element rather than by
     animating `width`: width forces layout on every scroll frame, a transform
     does not, and this runs on every scroll event on every page.

     It still runs under prefers-reduced-motion. The bar is an indicator of
     where you are, not an animation for its own sake, and removing it would
     take away orientation rather than restraint — the reduced-motion rule
     drops the easing instead. */

  function readingProgress() {
    if (document.querySelector(".progress-rail")) return;

    var rail = document.createElement("div");
    rail.className = "progress-rail";
    rail.setAttribute("aria-hidden", "true");
    var fill = document.createElement("div");
    fill.className = "progress-rail__fill";
    rail.appendChild(fill);
    document.body.appendChild(rail);

    var ticking = false;

    function update() {
      ticking = false;
      var doc = document.documentElement;
      var scrollable = doc.scrollHeight - window.innerHeight;
      // A page shorter than the viewport has nothing to track; showing a full
      // bar there would say "you have read everything" on arrival.
      if (scrollable <= 40) {
        fill.style.transform = "scaleX(0)";
        return;
      }
      var ratio = Math.min(1, Math.max(0, window.scrollY / scrollable));
      fill.style.transform = "scaleX(" + ratio.toFixed(4) + ")";
    }

    window.addEventListener("scroll", function () {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(update);
    }, { passive: true });

    window.addEventListener("resize", update, { passive: true });
    update();
  }

  LDCW.motion = {
    prefersReducedMotion: prefersReducedMotion,
    readingProgress: readingProgress,
    reveal: reveal,
    revealAll: revealAll,
    whenVisible: whenVisible,
    show: show,
    countUp: countUp,
    countUpOnView: countUpOnView,
    parallax: parallax,
    stickyHeader: stickyHeader,
  };
})(window.LDCW);
