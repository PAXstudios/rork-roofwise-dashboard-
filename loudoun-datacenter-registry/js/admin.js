/*
 * Moderation queue.
 *
 * This page is a convenience, not a security boundary — the database is. RLS
 * means a visitor without the admin role gets an empty array from listPending()
 * no matter what this file does, so the worst outcome of a bug here is an
 * unhelpful screen rather than a leak.
 *
 * In demo mode there are no accounts, so the queue is shown unauthenticated
 * against localStorage. That lets someone evaluate the workflow before setting
 * up Supabase, and the banner makes the situation obvious.
 */

(function (LDCW) {
  "use strict";

  var Store = LDCW.Store;
  var schema = LDCW.schema;
  var ui = LDCW.ui;
  var escape = schema.escapeHtml;

  var currentStatus = "pending";

  function show(id, visible) {
    var node = document.getElementById(id);
    if (node) node.hidden = !visible;
  }

  function notice(html) {
    var panel = document.getElementById("notice-panel");
    if (!panel) return;
    panel.innerHTML = html;
    panel.hidden = false;
  }

  /* ---- Queue rendering ---------------------------------------------------- */

  function privateBlock(report) {
    var rows = [];
    if (report.reporter_name) rows.push(["Name", report.reporter_name]);
    if (report.reporter_email) rows.push(["Email", report.reporter_email]);
    if (report.reporter_phone) rows.push(["Phone", report.reporter_phone]);
    if (report.address) rows.push(["Address", report.address]);
    rows.push(["Shareable", report.contact_ok ? "Yes — consented" : "No"]);

    if (typeof report.lat === "number") {
      rows.push(["Plotted at", report.lat.toFixed(5) + ", " + report.lng.toFixed(5)]);
    }

    return (
      '<div class="card" style="background:var(--bg-sunken);margin-top:var(--space-3)">' +
      '<h4 style="font-size:var(--text-xs);text-transform:uppercase;letter-spacing:.05em;color:var(--text-subtle)">' +
      "Private — never published</h4>" +
      '<dl class="popup__meta" style="font-size:var(--text-sm)">' +
      rows
        .map(function (pair) {
          return "<dt>" + escape(pair[0]) + "</dt><dd>" + escape(pair[1]) + "</dd>";
        })
        .join("") +
      "</dl></div>"
    );
  }

  function queueItem(report) {
    var categories = (report.categories || [])
      .map(function (key) {
        return '<span class="badge badge--neutral">' + escape(schema.categoryLabel(key)) + "</span>";
      })
      .join("");

    var photos = (report.photo_urls || [])
      .map(function (url) {
        return (
          '<a href="' +
          escape(url) +
          '" target="_blank" rel="noopener"><img src="' +
          escape(url) +
          '" alt="Attached photo" loading="lazy"></a>'
        );
      })
      .join("");

    var actions =
      report.status === "pending"
        ? '<button class="btn btn--success btn--sm" data-approve="' +
          escape(report.id) +
          '">Approve</button>' +
          '<button class="btn btn--danger btn--sm" data-reject="' +
          escape(report.id) +
          '">Reject</button>'
        : '<button class="btn btn--secondary btn--sm" data-pending="' +
          escape(report.id) +
          '">Move back to pending</button>';

    return (
      '<article class="card" style="margin-bottom:var(--space-4)">' +
      '<div class="report-card__head">' +
      '<h3 class="report-card__where">' +
      escape(report.locality || "—") +
      (report.zip ? " · " + escape(report.zip) : "") +
      "</h3>" +
      '<span class="report-card__when">' +
      escape(schema.formatDate(report.created_at)) +
      " · " +
      escape(schema.formatRelative(report.created_at)) +
      "</span>" +
      "</div>" +
      '<div class="badge-list" style="margin-bottom:var(--space-3)">' +
      categories +
      '<span class="badge badge--' +
      escape(report.status) +
      '">' +
      escape(report.status) +
      "</span>" +
      '<span class="severity severity--' +
      (Number(report.severity) || 0) +
      '"><span class="severity__dot" aria-hidden="true"></span>Impact ' +
      (Number(report.severity) || 0) +
      "/5</span>" +
      "</div>" +
      (report.facility_name || report.facility_operator
        ? '<p class="small muted">Facility: ' +
          escape(report.facility_name || "—") +
          (report.facility_operator ? " · " + escape(report.facility_operator) : "") +
          " · " +
          escape(schema.statusLabel(report.facility_status)) +
          "</p>"
        : "") +
      "<p>" +
      escape(report.description || "") +
      "</p>" +
      (report.other_notes
        ? '<p class="small muted"><strong>Also:</strong> ' + escape(report.other_notes) + "</p>"
        : "") +
      (photos ? '<div class="report-card__photos">' + photos + "</div>" : "") +
      privateBlock(report) +
      (report.moderation_note
        ? '<p class="small muted" style="margin-top:var(--space-3)"><strong>Note:</strong> ' +
          escape(report.moderation_note) +
          "</p>"
        : "") +
      '<div class="form-actions">' +
      actions +
      '<code class="tiny">' +
      escape(report.id) +
      "</code>" +
      "</div>" +
      "</article>"
    );
  }

  function bindActions(container) {
    function act(id, status, promptText) {
      var note = null;
      if (promptText) {
        note = window.prompt(promptText, "");
        if (note === null) return; // cancelled
      }
      Store.moderate(id, status, note)
        .then(loadQueue)
        .catch(function (error) {
          window.alert(error.message || "Couldn't update that report.");
        });
    }

    container.querySelectorAll("[data-approve]").forEach(function (button) {
      button.addEventListener("click", function () {
        act(button.getAttribute("data-approve"), "approved", null);
      });
    });

    container.querySelectorAll("[data-reject]").forEach(function (button) {
      button.addEventListener("click", function () {
        act(
          button.getAttribute("data-reject"),
          "rejected",
          "Why is this being rejected? (for your records — never published)"
        );
      });
    });

    container.querySelectorAll("[data-pending]").forEach(function (button) {
      button.addEventListener("click", function () {
        act(button.getAttribute("data-pending"), "pending", null);
      });
    });
  }

  function loadQueue() {
    var container = document.getElementById("queue");
    ui.showLoading(container, "Loading queue…");

    return Store.listPending({ status: currentStatus })
      .then(function (reports) {
        if (!reports.length) {
          container.innerHTML =
            '<div class="empty-state"><p class="empty-state__title">Nothing ' +
            escape(currentStatus === "pending" ? "waiting for review" : currentStatus) +
            "</p><p>" +
            escape(
              currentStatus === "pending"
                ? "The queue is clear."
                : "No reports have that status yet."
            ) +
            "</p></div>";
          return;
        }
        container.innerHTML = reports.map(queueItem).join("");
        bindActions(container);
      })
      .catch(function (error) {
        ui.showError(container, error);
      });
  }

  /* ---- Session ------------------------------------------------------------ */

  function enterQueue(userLabel) {
    show("signin-panel", false);
    show("queue-panel", true);
    var label = document.getElementById("signed-in-as");
    if (label) label.textContent = userLabel || "";
    loadQueue();
  }

  function bindSignIn() {
    var form = document.getElementById("signin-form");
    if (!form) return;

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      var status = document.getElementById("signin-status");
      var button = document.getElementById("signin-button");
      status.textContent = "Signing in…";
      status.className = "form-status";
      button.disabled = true;

      Store.signIn(
        document.getElementById("email").value.trim(),
        document.getElementById("password").value
      )
        .then(function () {
          return Store.isAdmin();
        })
        .then(function (isAdmin) {
          button.disabled = false;
          if (!isAdmin) {
            status.textContent =
              "That account signed in, but it isn't a moderator. See sql/04_admin.sql for how to grant the role.";
            status.className = "form-status form-status--error";
            return Store.signOut();
          }
          status.textContent = "";
          return Store.currentUser().then(function (user) {
            enterQueue(user ? user.email : "");
          });
        })
        .catch(function (error) {
          button.disabled = false;
          status.textContent = error.message || "Sign-in failed.";
          status.className = "form-status form-status--error";
        });
    });
  }

  function bindControls() {
    var select = document.getElementById("queue-status");
    if (select) {
      select.addEventListener("change", function () {
        currentStatus = select.value;
        loadQueue();
      });
    }

    var refresh = document.getElementById("refresh");
    if (refresh) refresh.addEventListener("click", loadQueue);

    var signout = document.getElementById("signout");
    if (signout) {
      signout.addEventListener("click", function () {
        Store.signOut().then(function () {
          window.location.reload();
        });
      });
    }
  }

  /* ---- Boot --------------------------------------------------------------- */

  function init() {
    bindControls();

    if (Store.isDemo) {
      // No accounts exist in demo mode, so show the queue directly and be very
      // clear about why there was no password prompt.
      notice(
        '<div class="banner banner--warning" style="margin-bottom:var(--space-4)">' +
          ui.icon("warning") +
          "<div><strong>Demo mode — no sign-in required, and none is possible.</strong> " +
          "This queue is reading your browser's local storage. On a live deployment this page " +
          "requires a moderator account and the database refuses to return anything to anyone " +
          'else. See <a href="about.html#demo-mode">connecting a database</a>.</div></div>'
      );
      show("queue-panel", true);
      var signedInAs = document.getElementById("signed-in-as");
      if (signedInAs) signedInAs.textContent = "demo mode";
      var signout = document.getElementById("signout");
      if (signout) signout.hidden = true;
      loadQueue();
      return;
    }

    bindSignIn();

    Store.isAdmin()
      .then(function (isAdmin) {
        if (isAdmin) {
          return Store.currentUser().then(function (user) {
            enterQueue(user ? user.email : "");
          });
        }
        show("signin-panel", true);
      })
      .catch(function () {
        show("signin-panel", true);
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})(window.LDCW);
