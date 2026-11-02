// Three moments of one conversation. The stage is the only stateful surface on the page, so the
// page keeps working with scripting off: the first scene is already in the markup.
const stage = document.querySelector("[data-mode]");
const buttons = Array.from(document.querySelectorAll("[data-scene]"));

const scenes = {
  speaking: {
    title: "Music steps back.",
    detail:
      "ChatGPT starts replying, and Apple Music pauses on the same beat. Your track, queue and position stay exactly where they were.",
    state: "pause issued · 190 ms after onset",
    ai: "speaking",
    music: "paused",
  },
  answering: {
    title: "It waits for your turn.",
    detail:
      "You start talking. Music stays paused for the conversation hold, so the reply does not jump back between the two of you.",
    state: "conversation hold · 12 s, adjustable",
    ai: "listening",
    music: "still paused",
  },
  quiet: {
    title: "Music comes home.",
    detail:
      "Nobody has spoken for the whole quiet interval. Oreja hands playback back at the level you chose, exactly where you left it.",
    state: "resume issued · back at 100%",
    ai: "quiet",
    music: "playing",
  },
};

function show(name) {
  const scene = scenes[name];
  if (!stage || !scene) return;

  stage.dataset.mode = name;
  const copy = stage.querySelector(".stage-copy");
  const title = stage.querySelector("[data-scene-title]");
  const detail = stage.querySelector("[data-scene-detail]");
  const state = stage.querySelector("[data-scene-state]");
  const ai = stage.querySelector("[data-row-ai]");
  const music = stage.querySelector("[data-row-music]");

  if (copy) {
    // New copy fades in rather than teleporting. The animation is one-shot and the resting style is
    // opacity 1, so a browser that never runs it (or a throttled tab) still shows the text.
    copy.classList.remove("scene-in");
    void copy.offsetWidth;
    copy.classList.add("scene-in");
  }

  if (title) title.textContent = scene.title;
  if (detail) detail.textContent = scene.detail;
  if (state) state.textContent = scene.state;
  if (ai) ai.textContent = scene.ai;
  if (music) music.textContent = scene.music;

  for (const button of buttons) {
    button.setAttribute("aria-pressed", String(button.dataset.scene === name));
  }
}

for (const button of buttons) {
  button.addEventListener("click", () => show(button.dataset.scene));
}
