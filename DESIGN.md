# Oreja visual direction

<!-- impeccable:design-schema 1 -->

## Direction

Oreja is a warm, character-led product about one small handoff: an AI voice gets the room, then the
music gets it back. Vincent — a pixel painter in a straw hat, one ear bandaged, one ear listening —
carries the product's namesake and does the explaining before a single paragraph of architecture.

## First viewport

The landing page opens on a painted night: indigo star field with two painted spirals, a low hill
line with a cypress, a cream headline in heavy Manrope with one italic line in wheat, and Vincent
standing on the hill at the right with a small translucent readout beside him. The painting is
alive — currents turn, moonlight crosses the clouds — while the character stays perfectly still.
The documentation page keeps the warm-paper system below, so the two surfaces are night and paper
rather than one theme stretched over both.

The first viewport should feel like a painting that happens to be a product page, not a SaaS hero.

## Visual world

- Material: warm white paper, charcoal ink, apricot for the character, coral for the listening light.
- Coral has three jobs and three values, never interchangeable: `--coral` (#e77952) is decoration
  only at 2.71:1 on paper, `--coral-deep` (#c95f3c) is for text at 24px and above at 3.79:1, and
  `--coral-ink` (#a7472a) is the only one allowed for small text and focus rings, at 5.5:1 on
  paper and 4.91:1 on the apricot wash. `--coral-ink` is the same value as
  `OrejaTheme.Palette.accent`, so the site and the app cannot drift apart.
- Composition: a full-bleed painted sky, one column of copy on the left, the character standing on
  the horizon at the right, and small mono labels for measurements. Nothing is industrial.
- Type: Manrope for display and UI on the site; the system sans in the app. Monospace is reserved for
  timings, percentages and version labels.
- Controls: pill buttons, black primary actions, rounded chips for the three conversation moments.
  Active states are unmistakable through position, colour and label.
- Motion: the painting moves, Vincent does not. On the site he is one still frame — no blink, bob,
  float or parallax, on scroll or otherwise — and the life in the first screen comes from the paint:
  three masked currents at 41 s, 57 s and 68 s, a moonlight band at 38 s, and a star field with
  embers and a rare shooting star. In the app he holds the idle frame and switches to listening, or
  to the ouch frame on a click (the bandage leaves his head) with a two-pixel shake. Interface
  transitions stay at 160–260 ms. Reduced motion stops every loop and keeps each state legible in
  text.
- Scroll: the landing page runs on the scroll-craft engine (`site/scrollcraft.js`, unedited). A
  pinned act holds the conversation while three moments cross over, a rail pans the three behaviors
  sideways, and the rest of the page is ordinary flow with one reveal per section. The signature
  move is the conversation rail: scroll drives the AI and Apple Music levels the app would actually
  report. `docs/scroll-craft.md` has the brief and the score.
- Native app: the same paper/card/ink/coral system, Vincent at 80 pt in the panel and in Settings,
  rounded cards at 18 pt.

## HeyTaby reference translation

Borrow the reference's qualities, not its identity: a character in the first viewport, short human
copy, one interactive "pick a moment and watch" demo, generous rounded controls, and a
local/private story that is demonstrated rather than buried. Do not copy Taby's character, logo,
illustrations, layout or wording. Oreja's own artefact is a five-frame pixel ear (idle, blink,
listening, listening blink, ouch).

## Product truth

Oreja is a macOS menu bar app for ChatGPT and Apple Music. It reacts to audio level, not transcript
content; it can pause or lower Music; it restores the configured return volume; it works locally; and
the current build is ad-hoc signed and not notarized.

## Responsive behavior

Desktop keeps the character between the floating cards with the headline above. Narrow screens stack
the headline, character and download action, hide the floating cards, and keep the same copy in the
scene caption so nothing is lost. The stage becomes a single column.

## Accessibility

Semantic headings, visible focus, reduced-motion support, readable contrast, keyboard-operable
controls, a text explanation for every animated state, and a `role="img"` label that describes
Vincent rather than leaving a decorative hole in the page.

## Page grammar

Every section once opened with the same small coral kicker, and every feature card carried a
`01 ·` counter. Both are machine-made rhythm rather than information, so the headings now carry
their own weight: Privacy and Verification keep a kicker, the other four sections do not, and the
card labels read Listen, Choose, Return. The page closes on the download card rather than trailing
away through the FAQ, which now sits above it.

## Review pass, November 2026

Run with `better-interface` and its six domain skills (accessibility, layout, writing, typography,
colors, UI), then `scroll-craft` and `humanizer` for grammar and copy. Findings that were fixed,
with the evidence that produced them:

| Finding | Before | After |
| --- | --- | --- |
| Section copy had no gutter below 900px | `.section`, `.hero`, `.band-wrap` and `.docs-hero` set a `0` inline padding shorthand that beat `.container` | vertical-only `padding-block`, so 320px copy insets 18px |
| Focus ring below 3:1 | `outline: 2px solid var(--coral)` at 2.71:1 | `--coral-ink` at 5.5:1, verified by real Tab presses in Chrome |
| Eyebrow text below 4.5:1 | `--coral-deep` at 11.5px, 3.79:1 | `--coral-ink`, 5.5:1 |
| Button hover text below 4.5:1 | white on `--coral-deep`, 4.05:1 | white on `--coral-ink`, 5.87:1 |
| Horizontal overflow | 352px document in a 320px viewport, 845px at 768px | glow inset and float offsets constrained; 320/390/768/1280 all measure equal to their viewport |
| Hover styles latched on touch | six `:hover` rules outside any media query | all gated behind `@media (hover: hover) and (pointer: fine)` |
| Text links under the 24px target floor | 22–23px tall | `min-height: 24px` on nav, footer and docs-nav links |
| Docs page wider than the phone | `grid-template-columns: 1fr` sized to the widest `<pre>` | `minmax(0, 1fr)`, and the three tables are keyboard-scrollable labelled regions |
| Readouts shifted while changing | proportional figures | `font-variant-numeric: tabular-nums` |
| Body text ignored reader font size | `16.5px` | `1.03rem` |
| Dark-mode character halo read as brown | one 62% apricot glow for both themes | dark override at 22% |

Sentences that carried AI tells were rewritten, not deleted: the hero sub lost its doubled "room",
the scene caption lost a clipped "never to the room" tail, the third card's fragment row became one
sentence, the privacy heading states both halves of a real claim, and no em dash remains in visible
copy. The claims, numbers and caveats are unchanged.

Deliberately not taken from `scroll-craft`: a filmic scroll grammar with generated photographic
planes. Oreja is an illustrated, quiet utility, and its signature move is the moment picker that
already rewrites the stage, so the page keeps its single static character and its blink.
