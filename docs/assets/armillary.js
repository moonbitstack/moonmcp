/* moonmcp · Armillary — shared page behaviour.
   No libraries. Plain ES, guarded for reduced motion. */
(function () {
  "use strict";
  var root = document.documentElement;

  /* theme: night is the default celestial moment; dawn is the toggle */
  var stored = null;
  try { stored = localStorage.getItem("moonmcp-theme"); } catch (e) {}
  if (stored === "light" || stored === "dark") {
    root.setAttribute("data-theme", stored);
  } else if (!root.getAttribute("data-theme")) {
    root.setAttribute("data-theme", "dark");
  }
  document.querySelectorAll("[data-theme-toggle]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var cur = root.getAttribute("data-theme") === "light" ? "dark" : "light";
      root.setAttribute("data-theme", cur);
      try { localStorage.setItem("moonmcp-theme", cur); } catch (e) {}
    });
  });

  /* scrollbar thumb hidden while parked at the top (docs.md) */
  var sync = function () { root.classList.toggle("at-top", window.scrollY <= 0); };
  window.addEventListener("scroll", sync, { passive: true });
  sync();

  /* scroll reveal — the page "breathes" in */
  var reveals = document.querySelectorAll(".reveal");
  if (reveals.length && "IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -8% 0px" });
    reveals.forEach(function (r) { io.observe(r); });
  } else {
    reveals.forEach(function (r) { r.classList.add("in"); });
  }

  /* copy buttons */
  document.querySelectorAll("[data-copy]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var text = btn.getAttribute("data-copy");
      var done = function () {
        var t = btn.textContent; btn.textContent = "copied"; btn.classList.add("ok");
        setTimeout(function () { btn.textContent = t; btn.classList.remove("ok"); }, 1100);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () {});
      }
    });
  });

  /* active nav / sidebar link */
  var links = Array.prototype.slice.call(document.querySelectorAll(".side-nav a, .nav .links a"));
  if (links.length && "IntersectionObserver" in window) {
    var map = {};
    links.forEach(function (a) {
      var id = a.getAttribute("href");
      if (id && id.charAt(0) === "#") map[id.slice(1)] = a;
    });
    var spy = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (e.isIntersecting) {
          links.forEach(function (a) { a.classList.remove("active"); });
          var a = map[e.target.id];
          if (a) a.classList.add("active");
        }
      });
    }, { rootMargin: "-12% 0px -78% 0px" });
    document.querySelectorAll("section[id], main[id], .section[id]").forEach(function (s) { spy.observe(s); });
  }
})();
