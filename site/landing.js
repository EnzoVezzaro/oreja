// The page's continuous motion: a star field with slow embers, one waveform scrubbed by the
// scroll, the sunrise at the end, and two small pieces of character. Nothing here decides pause
// or resume: the canvas draws the two levels the app reports, and the act's progress is read back
// from the engine's published --sc-p.

if (window.PageMotion) {
  PageMotion.mount(document.body);
}

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const clamp01 = (value) => Math.min(1, Math.max(0, value));

/* ------------------------------------------------------------------ chrome -- */

const header = document.querySelector(".n-header");
const progress = document.querySelector("[data-progress]");
const waveCanvas = document.querySelector("[data-wave]");
const storyAct = document.querySelector("#story");
const dawnSection = document.querySelector("[data-dawn]");
const aiBar = document.querySelector("[data-level-ai]");
const musicBar = document.querySelector("[data-level-music]");
const aiValue = document.querySelector("[data-value-ai]");
const musicValue = document.querySelector("[data-value-music]");
const playhead = document.querySelector("[data-playhead]");
const momentLabels = Array.from(document.querySelectorAll("[data-moment]"));

const waveCtx = waveCanvas ? waveCanvas.getContext("2d") : null;
let waveWidth = 0;
let waveHeight = 0;
// Every bar's silhouette, computed once per resize. Recomputing a hash and a sine for ~180 bars
// twice per band on every scroll frame was the single most expensive thing this page did while
// scrolling; the shape of each bar never changes, only how tall it is allowed to be.
let waveShapes = null;

function buildWaveShapes() {
  if (!waveWidth) return;
  const step = waveWidth < 720 ? 5 : 7;
  const count = Math.max(0, Math.ceil((waveWidth - 52) / step));
  waveShapes = [1.7, 4.3].map((seed) => {
    const shape = new Float32Array(count);
    for (let i = 0; i < count; i += 1) {
      const grain = hash(i, seed);
      shape[i] = (0.32 + 0.68 * grain) * (0.72 + 0.28 * Math.sin(i * 0.21 + seed * 2.4));
    }
    return shape;
  });
}

function sizeWave() {
  if (!waveCanvas) return;
  const rect = waveCanvas.getBoundingClientRect();
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  waveWidth = Math.max(1, rect.width);
  waveHeight = Math.max(1, rect.height);
  waveCanvas.width = Math.round(waveWidth * dpr);
  waveCanvas.height = Math.round(waveHeight * dpr);
  waveCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  buildWaveShapes();
  lastWaveP = -1;
}

// The engine owns the measurement, including the pin travel. Reading its number back beats
// recomputing geometry here: one source of truth for how far into the act we are.
function actProgress() {
  if (!storyAct) return 0;
  const raw = getComputedStyle(storyAct).getPropertyValue("--sc-p");
  const value = parseFloat(raw);
  return Number.isFinite(value) ? clamp01(value) : 0;
}

function hash(i, seed) {
  const x = Math.sin(i * 12.9898 + seed * 78.233) * 43758.5453;
  return x - Math.floor(x);
}

function levelAt(p) {
  // The shape the app reports, drawn: the reply takes the room, the hold keeps it, then the
  // music returns at the chosen level.
  if (p < 0.34) return { ai: 1 - p * 0.35, music: 0.03 };
  if (p < 0.62) return { ai: 0.88 - (p - 0.34) * 2.4, music: 0.03 };
  return { ai: Math.max(0.015, 0.2 - (p - 0.62) * 0.5), music: clamp01((p - 0.6) / 0.26) };
}

let lastWaveP = -1;

function drawWave(p) {
  if (!waveCtx || !waveWidth || !waveShapes) return;
  // A sub-pixel change is not visible on a 2 px bar, so it is not worth a repaint either.
  if (Math.abs(p - lastWaveP) < 0.0015) return;
  lastWaveP = p;

  const levels = levelAt(p);
  const w = waveWidth;
  const h = waveHeight;
  waveCtx.clearRect(0, 0, w, h);

  const step = w < 720 ? 5 : 7;
  const barWidth = step - 3;
  const scratch = 26;
  const aiY = h * 0.63;
  const musicY = h * 0.81;
  const amplitude = Math.min(h * 0.1, 96);

  // One pass per bar, two rectangles: the faint halo behind and the bar itself.
  function band(center, env, shape, color, halo) {
    if (env <= 0.031) return;
    const haloColor = halo;
    const barColor = color;
    for (let i = 0, x = scratch; x < w - scratch; i += 1, x += step) {
      const size = Math.max(1, env * amplitude * shape[i]);
      waveCtx.fillStyle = haloColor;
      waveCtx.fillRect(x - 1, center - size - 1, barWidth + 2, size * 2 + 2);
      waveCtx.fillStyle = barColor;
      waveCtx.fillRect(x, center - size, barWidth, size * 2);
    }
  }

  band(aiY, levels.ai, waveShapes[0], "rgba(243, 205, 128, 0.92)", "rgba(239, 195, 106, 0.1)");
  band(musicY, levels.music, waveShapes[1], "rgba(244, 152, 114, 0.9)", "rgba(240, 138, 95, 0.1)");

  // Centre lines, then the playhead.
  waveCtx.strokeStyle = "rgba(246, 236, 217, 0.12)";
  waveCtx.lineWidth = 1;
  for (const y of [aiY, musicY]) {
    waveCtx.beginPath();
    waveCtx.moveTo(scratch, y + 0.5);
    waveCtx.lineTo(w - scratch, y + 0.5);
    waveCtx.stroke();
  }

  const headX = scratch + p * (w - scratch * 2);
  const gradient = waveCtx.createLinearGradient(0, h * 0.4, 0, h);
  gradient.addColorStop(0, "rgba(246, 236, 217, 0.5)");
  gradient.addColorStop(1, "rgba(246, 236, 217, 0)");
  waveCtx.strokeStyle = gradient;
  waveCtx.lineWidth = 1;
  waveCtx.beginPath();
  waveCtx.moveTo(headX + 0.5, h * 0.4);
  waveCtx.lineTo(headX + 0.5, h);
  waveCtx.stroke();
}

function paintAct(p) {
  if (!storyAct) return;
  const value = typeof p === "number" ? p : actProgress();
  const levels = levelAt(value);

  // The bars move by a rounding error most frames. Writing an identical string still invalidates
  // style, so the write is skipped unless the rendered value actually changes.
  if (aiBar) setWidth(aiBar, clamp01(levels.ai) * 100);
  if (musicBar) setWidth(musicBar, clamp01(levels.music) * 100);
  const aiText = value < 0.36 ? "speaking" : value < 0.64 ? "listening" : "quiet";
  if (aiValue && aiValue.textContent !== aiText) aiValue.textContent = aiText;
  const musicText = value < 0.6 ? "paused" : levels.music > 0.94 ? "100%" : "returning";
  if (musicValue && musicValue.textContent !== musicText) musicValue.textContent = musicText;
  if (playhead) setPercent(playhead, value * 100);

  const live = value < 0.36 ? "speaking" : value < 0.64 ? "answering" : "quiet";
  for (const label of momentLabels) {
    label.classList.toggle("is-live", label.dataset.moment === live);
  }

  drawWave(value);
}

// Cached writers: the DOM is only touched when the rendered number changes, which keeps a slow
// scroll from recalculating style for elements that did not move.
const widthCache = new WeakMap();
const percentCache = new WeakMap();

function setWidth(el, percent) {
  const next = percent.toFixed(1) + "%";
  if (widthCache.get(el) === next) return;
  widthCache.set(el, next);
  el.style.width = next;
}

function setPercent(el, percent) {
  const next = percent.toFixed(2) + "%";
  if (percentCache.get(el) === next) return;
  percentCache.set(el, next);
  el.style.left = next;
}

/* -------------------------------------------------------------------- dawn -- */

/* The sunrise is a custom property on the section, so every write invalidates style for its whole
   subtree. Two decimal places are all the paint can show, so the rest of the writes are dropped. */
let lastDawn = -1;
let dawnTop = 0;
let dawnTravel = 1;

function measureDawn() {
  if (!dawnSection) return;
  dawnTop = dawnSection.getBoundingClientRect().top + window.scrollY;
  dawnTravel = Math.max(1, window.innerHeight * 0.85);
  lastDawn = -1;
}

function paintDawn() {
  if (!dawnSection) return;
  const value = clamp01((window.innerHeight + window.scrollY - dawnTop) / dawnTravel);
  const rounded = Math.round(value * 100) / 100;
  if (rounded === lastDawn) return;
  lastDawn = rounded;
  dawnSection.style.setProperty("--dawn", rounded.toFixed(2));
}

/* ------------------------------------------------------------------ scroll -- */

let scrollQueued = false;
function onScroll() {
  if (scrollQueued) return;
  scrollQueued = true;
  requestAnimationFrame(() => {
    scrollQueued = false;
    const y = window.scrollY;
    if (header) header.classList.toggle("is-scrolled", y > 36);
    if (progress) {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      progress.style.width = (max > 0 ? (y / max) * 100 : 0).toFixed(2) + "%";
    }
    paintAct(actProgress());
    paintDawn();
  });
}

window.addEventListener("scroll", onScroll, { passive: true });
window.addEventListener("resize", () => {
  sizeWave();
  measureDawn();
  paintAct();
  paintDawn();
});

sizeWave();
measureDawn();
paintAct();
paintDawn();
onScroll();

// Sections above the sunrise can change height after the first paint (fonts, the engine's pin
// travel), so its offset is re-measured when the layout settles rather than on every frame.
window.addEventListener("load", () => { measureDawn(); paintDawn(); }, { once: true });
if ("ResizeObserver" in window) {
  new ResizeObserver(() => { measureDawn(); paintDawn(); }).observe(document.body);
}

/* ---------------------------------------------------------------- starfield -- */

const starCanvas = document.querySelector("[data-starfield]");
const starCtx = starCanvas ? starCanvas.getContext("2d") : null;
const stars = [];
const embers = [];
let shootingStar = null;
let nextShootingStar = 7000;
let starWidth = 0;
let starHeight = 0;
let heroVisible = true;

function seedStars() {
  if (!starCanvas) return;
  const rect = starCanvas.getBoundingClientRect();
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  starWidth = Math.max(1, rect.width);
  starHeight = Math.max(1, rect.height);
  starCanvas.width = Math.round(starWidth * dpr);
  starCanvas.height = Math.round(starHeight * dpr);
  starCtx.setTransform(dpr, 0, 0, dpr, 0, 0);

  stars.length = 0;
  const count = Math.round((starWidth * starHeight) / 14000);
  for (let i = 0; i < Math.min(150, count); i += 1) {
    stars.push({
      x: Math.random() * starWidth,
      y: Math.random() * starHeight * 0.78,
      r: 0.6 + Math.random() * 1.2,
      phase: Math.random() * Math.PI * 2,
      speed: 0.5 + Math.random() * 1.6,
      warm: Math.random() > 0.86,
    });
  }

  embers.length = 0;
  for (let i = 0; i < 12; i += 1) {
    embers.push({
      x: Math.random() * starWidth,
      y: starHeight * (0.35 + Math.random() * 0.5),
      r: 0.9 + Math.random() * 1.5,
      drift: 4 + Math.random() * 9,
      sway: 6 + Math.random() * 18,
      phase: Math.random() * Math.PI * 2,
      speed: 0.15 + Math.random() * 0.35,
      alpha: 0.18 + Math.random() * 0.4,
    });
  }
}

function drawStars(time) {
  if (!starCtx || !starWidth) return;
  starCtx.clearRect(0, 0, starWidth, starHeight);

  for (const star of stars) {
    const twinkle = 0.45 + 0.55 * (0.5 + 0.5 * Math.sin(time * 0.001 * star.speed + star.phase));
    starCtx.beginPath();
    starCtx.fillStyle = star.warm
      ? `rgba(246, 226, 188, ${(0.85 * twinkle).toFixed(3)})`
      : `rgba(238, 243, 255, ${(0.8 * twinkle).toFixed(3)})`;
    starCtx.arc(star.x, star.y, star.r, 0, Math.PI * 2);
    starCtx.fill();
  }

  for (const ember of embers) {
    const y = ember.y - ((time * 0.001 * ember.drift) % 220);
    const x = ember.x + Math.sin(time * 0.0006 + ember.phase) * ember.sway;
    const glow = ember.alpha * (0.6 + 0.4 * Math.sin(time * 0.001 * ember.speed * 3 + ember.phase));
    const gradient = starCtx.createRadialGradient(x, y, 0, x, y, ember.r * 6);
    gradient.addColorStop(0, `rgba(255, 186, 132, ${glow.toFixed(3)})`);
    gradient.addColorStop(1, "rgba(255, 186, 132, 0)");
    starCtx.fillStyle = gradient;
    starCtx.beginPath();
    starCtx.arc(x, y, ember.r * 6, 0, Math.PI * 2);
    starCtx.fill();
  }

  if (shootingStar) {
    const life = shootingStar.life;
    starCtx.strokeStyle = `rgba(246, 236, 217, ${(life * 0.7).toFixed(3)})`;
    starCtx.lineWidth = 1.4;
    starCtx.beginPath();
    starCtx.moveTo(shootingStar.x, shootingStar.y);
    starCtx.lineTo(shootingStar.x - shootingStar.vx * 8, shootingStar.y - shootingStar.vy * 8);
    starCtx.stroke();
  }
}

function tickStars(time) {
  if (!starCtx) return;
  if (heroVisible && !reduceMotion) {
    if (!shootingStar && time > nextShootingStar) {
      shootingStar = {
        x: starWidth * (0.3 + Math.random() * 0.6),
        y: starHeight * (0.06 + Math.random() * 0.16),
        vx: 6 + Math.random() * 4,
        vy: 2 + Math.random() * 2,
        life: 1,
      };
      nextShootingStar = time + 9000 + Math.random() * 12000;
    }
    if (shootingStar) {
      shootingStar.x += shootingStar.vx;
      shootingStar.y += shootingStar.vy;
      shootingStar.life -= 0.035;
      if (shootingStar.life <= 0) shootingStar = null;
    }
    drawStars(time);
    requestAnimationFrame(tickStars);
  }
}

if (starCanvas && starCtx) {
  seedStars();
  const hero = document.querySelector(".n-hero");
  if (hero && "IntersectionObserver" in window) {
    new IntersectionObserver(
      (entries) => {
        heroVisible = entries[0].isIntersecting;
        if (heroVisible && !reduceMotion) requestAnimationFrame(tickStars);
      },
      { threshold: 0.02 }
    ).observe(hero);
  }
  if (reduceMotion) drawStars(0);
  else requestAnimationFrame(tickStars);
}

// The hero's painted layers turn for as long as the page is open, and each one is a full-viewport
// raster rotating under a mask. Offscreen they still cost the compositor every frame, so they are
// parked once the hero has left the viewport and resumed when it comes back.
const heroSection = document.querySelector(".n-hero");
if (heroSection && "IntersectionObserver" in window) {
  new IntersectionObserver(
    (entries) => heroSection.classList.toggle("is-parked", !entries[0].isIntersecting),
    { rootMargin: "160px" }
  ).observe(heroSection);
}

/* -------------------------------------------------------- the ear, and the egg -- */

const heroVincent = document.querySelector("[data-vincent-hero]");
const eggButton = document.querySelector("[data-egg]");
const eggNote = document.querySelector("[data-egg-note]");
let blinkTimer = 0;
let eggTimer = 0;
let noteTimer = 0;
let isOuching = false;

/* The app's numbers: the shake occupies 810ms, and with reduced motion he simply holds the ouch
   frame for 900ms. Same sprite, same timings, same joke. */
const OUCH_MS = 810;
const OUCH_REDUCED_MS = 900;
const NOTE_MS = 1900;

function scheduleBlink() {
  if (!heroVincent || reduceMotion) return;
  clearTimeout(blinkTimer);
  blinkTimer = window.setTimeout(() => {
    if (!heroVincent.classList.contains("is-ouch")) {
      heroVincent.classList.add("is-blink");
      window.setTimeout(() => heroVincent.classList.remove("is-blink"), 140);
    }
    scheduleBlink();
  }, 3800 + Math.random() * 4200);
}

if (heroVincent) scheduleBlink();

function snipHero() {
  if (!heroVincent || !eggButton || isOuching) return;
  isOuching = true;
  heroVincent.classList.remove("is-blink");
  // The app takes 4% of the sprite's size, rounded to whole pixels, so the step follows whatever
  // width the hero happens to render at instead of being tuned for one breakpoint.
  const step = Math.max(1, Math.round(heroVincent.getBoundingClientRect().width * 0.04));
  heroVincent.style.setProperty("--ouch-step", `${step}px`);
  heroVincent.classList.add("is-ouch");
  if (eggNote) {
    eggNote.textContent = "Careful. He uses that one.";
    eggNote.classList.add("is-shown");
  }
  clearTimeout(eggTimer);
  eggTimer = window.setTimeout(() => {
    heroVincent.classList.remove("is-ouch");
    isOuching = false;
  }, reduceMotion ? OUCH_REDUCED_MS : OUCH_MS);
  // The line outlives the sprite: 810ms is the app's animation, not enough time to read anything.
  clearTimeout(noteTimer);
  noteTimer = window.setTimeout(() => eggNote?.classList.remove("is-shown"), NOTE_MS);
}

if (eggButton) eggButton.addEventListener("click", snipHero);

/* The copy column is a full-width panel stacked above the figure, so a click aimed at Vincent lands
   on empty space inside that panel instead of on his button — his shake never played at all. Rather
   than reorder the paint (the copy is meant to sit in front), forward clicks that fall inside his
   sprite box. Links and controls that happen to overlap him still win. */
const heroClickTarget = document.querySelector(".n-hero");
if (heroClickTarget && heroVincent) {
  heroClickTarget.addEventListener("click", (event) => {
    if (event.target.closest("[data-egg], a, button, input, select, textarea, label")) return;
    const box = heroVincent.getBoundingClientRect();
    const inside =
      event.clientX >= box.left &&
      event.clientX <= box.right &&
      event.clientY >= box.top &&
      event.clientY <= box.bottom;
    if (inside) snipHero();
  });
}

/* ------------------------------------------------------------- the desk scene -- */

/* The desk is one generated SVG (`assets/vincent-desk.svg`) made of named layers. It ships as an
   <img> so it renders with no JavaScript and no extra request logic, then this swaps the file for
   its own markup so night.css can animate the steam, the stars, the LED and the blink. Animation
   written inside the file would be a document of its own and would ignore the page's
   `prefers-reduced-motion`, which is the one thing it must not do. If the fetch fails — opened from
   disk with file://, or offline — the still image stays and the page is unchanged. */
const deskFigure = document.querySelector(".n-desk");
const deskImage = deskFigure ? deskFigure.querySelector("img") : null;

if (deskImage) {
  fetch(deskImage.getAttribute("src"))
    .then((response) => (response.ok ? response.text() : Promise.reject(new Error("desk"))))
    .then((markup) => {
      const svg = new DOMParser().parseFromString(markup, "image/svg+xml").documentElement;
      if (!svg || svg.nodeName.toLowerCase() !== "svg") return;
      svg.setAttribute("class", "n-desk-art");
      svg.setAttribute("aria-hidden", "true");
      svg.removeAttribute("role");
      svg.removeAttribute("aria-label");
      deskImage.replaceWith(svg);
    })
    .catch(() => {});
}

