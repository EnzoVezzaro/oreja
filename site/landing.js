// Two jobs, both small: mount the scroll engine, then keep the pinned conversation act in sync
// with the engine's published progress. Nothing here decides pause or resume. The page only shows
// what the app reports.

if (window.ScrollCraft) {
  ScrollCraft.mount(document.body);
}

const howAct = document.querySelector("#how");
const chips = Array.from(document.querySelectorAll("[data-scene]"));
const panels = Array.from(document.querySelectorAll("[data-scene-panel]"));
const railHead = document.querySelector("[data-conv-head]");
const aiBar = document.querySelector("[data-level-ai]");
const musicBar = document.querySelector("[data-level-music]");
const aiText = document.querySelector("[data-row-ai]");
const musicText = document.querySelector("[data-row-music]");

const moments = [
  { name: "speaking", at: 0.12, ai: 0.92, music: 0, aiLabel: "speaking", musicLabel: "paused" },
  { name: "answering", at: 0.5, ai: 0.34, music: 0, aiLabel: "listening", musicLabel: "paused" },
  { name: "quiet", at: 0.86, ai: 0.02, music: 1, aiLabel: "quiet", musicLabel: "100%" },
];

function clamp01(value) {
  return Math.min(1, Math.max(0, value));
}

// Progress as the engine published it on the act element. Reading it back beats recomputing the
// geometry here: the engine owns the measurement, including the pin travel.
function actProgress() {
  if (!howAct) return 0;
  const raw = getComputedStyle(howAct).getPropertyValue("--sc-p");
  const value = parseFloat(raw);
  return Number.isFinite(value) ? clamp01(value) : 0;
}

function momentAt(p) {
  // The cue windows overlap on purpose, so the chip follows the midpoint of each window rather
  // than its edge: a chip that flips while two panels are both half-lit reads as a glitch.
  if (p < 0.34) return 0;
  if (p < 0.66) return 1;
  return 2;
}

function paint() {
  const p = actProgress();
  const index = momentAt(p);

  // The rail is the signature: it is the scroll, drawn. The AI level falls as you travel and the
  // music level comes back at the end, which is the one behaviour the app exists for.
  const ai = p < 0.34 ? 0.92 : p < 0.62 ? 0.34 : 0.34 * (1 - clamp01((p - 0.62) / 0.16));
  const music = clamp01((p - 0.64) / 0.2);

  if (railHead) railHead.style.left = (p * 100).toFixed(2) + "%";
  if (aiBar) aiBar.style.width = (ai * 100).toFixed(1) + "%";
  if (musicBar) musicBar.style.width = (music * 100).toFixed(1) + "%";
  if (aiText) aiText.textContent = p < 0.34 ? "speaking" : p < 0.66 ? "listening" : "quiet";
  if (musicText) musicText.textContent = music > 0.98 ? "100%" : "paused";

  for (const chip of chips) {
    chip.setAttribute("aria-pressed", String(chip.dataset.scene === moments[index].name));
  }
  for (const panel of panels) {
    panel.dataset.active = String(panel.dataset.scenePanel === moments[index].name);
  }
}

function centreOf(index) {
  // Scroll to where that moment is at full strength, not to its first pixel.
  if (!howAct) return;
  const travel = Math.max(1, howAct.offsetHeight - window.innerHeight);
  const top = howAct.getBoundingClientRect().top + window.scrollY;
  window.scrollTo({ top: top + moments[index].at * travel, behavior: "smooth" });
}

for (const chip of chips) {
  chip.addEventListener("click", () => {
    const index = moments.findIndex((moment) => moment.name === chip.dataset.scene);
    if (index >= 0) centreOf(index);
  });
}

if (howAct) {
  let queued = false;
  const schedule = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      paint();
    });
  };
  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", schedule, { passive: true });
  paint();
}
