/*
 * Renders the contact address wherever a page has a [data-contact] or
 * #contact-block placeholder — but only if one has actually been configured.
 *
 * The placeholder text deliberately says "not configured yet" rather than
 * inventing a plausible-looking address: a contact route that silently goes
 * nowhere is worse than an honest gap, especially on a takedown page.
 */

(function () {
  "use strict";

  function render() {
    var email = (window.LDCW_CONFIG || {}).CONTACT_EMAIL;
    if (!email) return;

    var safe = String(email).replace(/[<>"']/g, "");
    var targets = document.querySelectorAll("#contact-block, [data-contact]");

    targets.forEach(function (node) {
      node.innerHTML = '<a href="mailto:' + safe + '">' + safe + "</a>";
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", render);
  } else {
    render();
  }
})();
