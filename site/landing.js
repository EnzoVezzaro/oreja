// The page's continuous motion: a star field with slow embers, one waveform scrubbed by the
// scroll, the sunrise at the end, and two small pieces of character. Nothing here decides pause
// or resume: the canvas draws the two levels the app reports, and the act's progress is read back
// from the engine's published --sc-p.

if (window.ScrollCraft) {
  ScrollCraft.mount(document.body);
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

function sizeWave() {
  if (!waveCanvas) return;
  const rect = waveCanvas.getBoundingClientRect();
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  waveWidth = Math.max(1, rect.width);
  waveHeight = Math.max(1, rect.height);
  waveCanvas.width = Math.round(waveWidth * dpr);
  waveCanvas.height = Math.round(waveHeight * dpr);
  waveCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
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

function drawWave() {
  if (!waveCtx || !waveWidth) return;
  const p = actProgress();
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

  function band(center, env, seed, color, halo) {
    if (env <= 0.031) return;
    waveCtx.fillStyle = halo;
    for (let x = scratch, i = 0; x < w - scratch; x += step, i += 1) {
      const grain = hash(i, seed);
      const shape = 0.32 + 0.68 * grain;
      const wave = 0.72 + 0.28 * Math.sin(i * 0.21 + seed * 2.4);
      const size = Math.max(1, env * amplitude * shape * wave);
      waveCtx.fillRect(x - 1, center - size - 1, barWidth + 2, size * 2 + 2);
    }
    waveCtx.fillStyle = color;
    for (let x = scratch, i = 0; x < w - scratch; x += step, i += 1) {
      const grain = hash(i, seed);
      const shape = 0.32 + 0.68 * grain;
      const wave = 0.72 + 0.28 * Math.sin(i * 0.21 + seed * 2.4);
      const size = Math.max(1, env * amplitude * shape * wave);
      waveCtx.fillRect(x, center - size, barWidth, size * 2);
    }
  }

  band(aiY, levels.ai, 1.7, "rgba(243, 205, 128, 0.92)", "rgba(239, 195, 106, 0.1)");
  band(musicY, levels.music, 4.3, "rgba(244, 152, 114, 0.9)", "rgba(240, 138, 95, 0.1)");

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

function paintAct() {
  if (!storyAct) return;
  const p = actProgress();
  const levels = levelAt(p);

  if (aiBar) aiBar.style.width = (clamp01(levels.ai) * 100).toFixed(1) + "%";
  if (musicBar) musicBar.style.width = (clamp01(levels.music) * 100).toFixed(1) + "%";
  if (aiValue) aiValue.textContent = p < 0.36 ? "speaking" : p < 0.64 ? "listening" : "quiet";
  if (musicValue) {
    musicValue.textContent = p < 0.6 ? "paused" : levels.music > 0.94 ? "100%" : "returning";
  }
  if (playhead) playhead.style.left = (p * 100).toFixed(2) + "%";

  const live = p < 0.36 ? "speaking" : p < 0.64 ? "answering" : "quiet";
  for (const label of momentLabels) {
    label.classList.toggle("is-live", label.dataset.moment === live);
  }

  drawWave();
}

/* -------------------------------------------------------------------- dawn -- */

function paintDawn() {
  if (!dawnSection) return;
  const rect = dawnSection.getBoundingClientRect();
  const travel = Math.max(1, window.innerHeight * 0.85);
  const value = clamp01((window.innerHeight - rect.top) / travel);
  dawnSection.style.setProperty("--dawn", value.toFixed(3));
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
    paintAct();
    paintDawn();
  });
}

window.addEventListener("scroll", onScroll, { passive: true });
window.addEventListener("resize", () => {
  sizeWave();
  paintAct();
  paintDawn();
});

sizeWave();
paintAct();
paintDawn();
onScroll();

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

/* -------------------------------------------------------- the ear, and the egg -- */

const heroVincent = document.querySelector("[data-vincent-hero]");
const eggButton = document.querySelector("[data-egg]");
const eggNote = document.querySelector("[data-egg-note]");
let blinkTimer = 0;
let eggTimer = 0;

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

if (eggButton) {
  eggButton.addEventListener("click", () => {
    heroVincent.classList.remove("is-blink");
    heroVincent.classList.add("is-ouch");
    if (eggNote) {
      eggNote.textContent = "Careful. He uses that one.";
      eggNote.classList.add("is-shown");
    }
    clearTimeout(eggTimer);
    eggTimer = window.setTimeout(() => {
      heroVincent.classList.remove("is-ouch");
      if (eggNote) eggNote.classList.remove("is-shown");
    }, 1900);
  });
}
