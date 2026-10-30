/* moonmcp · The Stone & Fire Tavern — shared page behaviour.
   No libraries. Plain ES, guarded for reduced motion. */
(function () {
  "use strict";
  var root = document.documentElement;

  /* theme: night is the default; noon is the toggle */
  var stored = null;
  try { stored = localStorage.getItem("moonmcp-theme"); } catch (e) {}
  if (stored === "light" || stored === "dark") {
    root.setAttribute("data-theme", stored);
  } else if (!root.getAttribute("data-theme")) {
    root.setAttribute("data-theme", "dark");
  }
  document.querySelectorAll("[data-theme-toggle]").forEach(function (btn) {
    btn.addEventListener("click", function (ev) {
      ev.preventDefault();
      var cur = root.getAttribute("data-theme") === "light" ? "dark" : "light";
      root.setAttribute("data-theme", cur);
      try { localStorage.setItem("moonmcp-theme", cur); } catch (e) {}
    });
  });

  /* the page's scroll bar shows while it moves or the pointer is at the right
     edge, and hides a moment after both stop */
  var idle = 0, near = false;
  var hideSoon = function () { clearTimeout(idle); idle = setTimeout(function () { if (!near) root.classList.remove("scrolling"); }, 1200); };
  window.addEventListener("scroll", function () { root.classList.add("scrolling"); hideSoon(); }, { passive: true });
  window.addEventListener("pointermove", function (e) {
    var was = near;
    near = e.pointerType === "mouse" && e.clientX >= root.clientWidth - 24;
    if (near) root.classList.add("scrolling"); else if (was) hideSoon();
  }, { passive: true });
  root.addEventListener("pointerleave", function () { near = false; hideSoon(); });

  /* copy buttons — the text is read from the block they sit in, so a snippet is
     never written twice in the page */
  document.querySelectorAll("button.copy").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var src = btn.parentNode.querySelector("pre, code");
      if (!src) return;
      var text = src.innerText;
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
