(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---- tiny critically-damped spring, used for the nav indicator and
     the cursor crosshair — both are continuously re-targeted, so a
     CSS transition would fight new input instead of blending it. ---- */
  function makeSpring({ stiffness = 340, damping = 34 } = {}) {
    let value = 0, target = 0, velocity = 0, raf = null, lastT = 0;
    let onUpdate = () => {};

    function step(now) {
      // dt in seconds, clamped so a dropped/backgrounded frame can't blow up the integration
      const dt = lastT ? Math.min((now - lastT) / 1000, 0.05) : 1 / 60;
      lastT = now;

      const force = (target - value) * stiffness;
      const damp = velocity * damping;
      const accel = force - damp;
      velocity += accel * dt;
      value += velocity * dt;
      onUpdate(value);

      if (Math.abs(target - value) > 0.01 || Math.abs(velocity) > 0.01) {
        raf = requestAnimationFrame(step);
      } else {
        value = target;
        onUpdate(value);
        raf = null;
        lastT = 0;
      }
    }

    return {
      set(t, immediate = false) {
        target = t;
        if (immediate) { value = t; velocity = 0; onUpdate(value); return; }
        if (!raf) raf = requestAnimationFrame(step);
      },
      subscribe(fn) { onUpdate = fn; },
    };
  }

  /* ------------------------------ nav underline ------------------------------ */
  const navLinks = Array.from(document.querySelectorAll(".nav-links a"));
  const indicator = document.getElementById("nav-indicator");
  const sections = navLinks
    .map((a) => document.querySelector(a.getAttribute("href")))
    .filter(Boolean);

  if (indicator && navLinks.length) {
    const xSpring = makeSpring();
    const wSpring = makeSpring();
    let currentX = 0, currentW = 0;

    xSpring.subscribe((v) => { currentX = v; render(); });
    wSpring.subscribe((v) => { currentW = v; render(); });

    function render() {
      indicator.style.transform = `translateX(${currentX}px)`;
      indicator.style.width = `${currentW}px`;
    }

    function moveTo(link, immediate = false) {
      const navRect = link.closest(".nav-links").getBoundingClientRect();
      const rect = link.getBoundingClientRect();
      xSpring.set(rect.left - navRect.left, immediate);
      wSpring.set(rect.width, immediate);
    }

    const first = navLinks[0];
    moveTo(first, true);
    first.classList.add("active");

    if (!reduceMotion && sections.length) {
      const io = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (!entry.isIntersecting) return;
            const idx = sections.indexOf(entry.target);
            if (idx === -1) return;
            navLinks.forEach((a) => a.classList.remove("active"));
            navLinks[idx].classList.add("active");
            moveTo(navLinks[idx]);
          });
        },
        { rootMargin: "-45% 0px -50% 0px" }
      );
      sections.forEach((s) => io.observe(s));
    }

    navLinks.forEach((a) => {
      a.addEventListener("mouseenter", () => moveTo(a));
      a.addEventListener("mouseleave", () => {
        const active = document.querySelector(".nav-links a.active");
        if (active) moveTo(active);
      });
    });

    window.addEventListener("resize", () => {
      const active = document.querySelector(".nav-links a.active") || first;
      moveTo(active, true);
    });
  }

  /* ------------------------------ scroll reveal ------------------------------ */
  const revealTargets = document.querySelectorAll("[data-reveal]");
  if (revealTargets.length) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("in-view");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.1, rootMargin: "0px 0px -8% 0px" }
    );
    revealTargets.forEach((el) => io.observe(el));
  }

  /* ------------------------------ cursor crosshair ---------------------------- */
  if (!reduceMotion && window.matchMedia("(hover: hover) and (pointer: fine)").matches) {
    const crosshair = document.getElementById("crosshair");
    if (crosshair) {
      const xSpring = makeSpring({ stiffness: 420, damping: 32 });
      const ySpring = makeSpring({ stiffness: 420, damping: 32 });
      let cx = 0, cy = 0;
      xSpring.subscribe((v) => { cx = v; paint(); });
      ySpring.subscribe((v) => { cy = v; paint(); });

      function paint() {
        crosshair.style.transform = `translate(${cx}px, ${cy}px)`;
      }

      let shown = false;
      window.addEventListener("pointermove", (e) => {
        xSpring.set(e.clientX);
        ySpring.set(e.clientY);
        if (!shown) {
          xSpring.set(e.clientX, true);
          ySpring.set(e.clientY, true);
          crosshair.classList.add("visible");
          shown = true;
        }
      });
      window.addEventListener("pointerleave", () => crosshair.classList.remove("visible"));
      document.addEventListener("pointerdown", () => crosshair.classList.remove("visible"));
    }
  }
})();
