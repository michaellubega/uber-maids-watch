/* UBER MAIDS WATCH — portal behaviour (no dependencies) */
(function () {
  "use strict";

  var header = document.querySelector(".site-header");
  var toggle = document.querySelector("[data-nav-toggle]");

  if (!header || !toggle) return;

  function setOpen(open) {
    header.classList.toggle("nav-open", open);
    toggle.setAttribute("aria-expanded", open ? "true" : "false");
  }

  toggle.addEventListener("click", function () {
    setOpen(!header.classList.contains("nav-open"));
  });

  // Close the menu after choosing a link.
  header.addEventListener("click", function (event) {
    if (event.target.closest(".site-nav a")) setOpen(false);
  });

  // Escape closes the menu and returns focus to the toggle.
  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && header.classList.contains("nav-open")) {
      setOpen(false);
      toggle.focus();
    }
  });

  // A resize past the mobile breakpoint should reset the menu state.
  var desktop = window.matchMedia("(min-width: 861px)");
  var reset = function (event) {
    if (event.matches) setOpen(false);
  };
  if (desktop.addEventListener) desktop.addEventListener("change", reset);
  else if (desktop.addListener) desktop.addListener(reset);
})();
