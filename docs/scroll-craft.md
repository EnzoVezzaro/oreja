# Scroll design (scroll-craft)

The landing page is a scroll-driven page built with the
[scroll-craft](https://github.com/nateherkai/scroll-craft) skill. This file records the decisions
that skill asks for (brief, grammar, score, signature move, verification) so a later change does not
have to reverse-engineer them from the CSS.

## Brief

Self-authored under the user's delegation ("work on the UI", "use this repo"). The subject is fixed
by the product and `docs/brand.md`, not invented here.

- **What it is.** A macOS menu bar app that pauses Apple Music while ChatGPT speaks and gives it back
  when the conversation goes quiet. Local only.
- **What the visitor must believe by the end.** Oreja reacts to the shape of a conversation, not to
  the words in it, and it does that without recording anything.
- **The one action.** Download the 0.1.0 build.
- **Assets.** No photography and no footage. The brand is genuinely illustrated: one generated pixel
  character, `site/assets/oreja-vincent.png`. Generating a photographic world here would contradict
  the brand, so the page is built from the illustration, the palette and real product states.
- **Vibe.** Warm paper, quiet, literal. Two families (Manrope + system mono), one accent family.

## Grammar: split stage, chaptered at the act level

Of the eight grammars, split stage fits the product best: the art column and its readouts hold while
the argument advances beside them. Filmic one-shot was refused (no footage, and a camera flight
would have to move the character), continuous world was refused for the same reason, and the
gallery, poster and cutlist grammars describe pages with no argument to make.

The page is therefore three movements, not a linked sequence: the static hero, the pinned
conversation, the lateral behaviors, then ordinary chapters (privacy, verification, FAQ, close).

## Feeling curve and the peak

| Act | Feeling | What causes it |
| --- | --- | --- |
| Hero | Recognition | The headline says the thing before any feature does; Vincent stands still beside it |
| Conversation (pinned) | Understanding | The same stage holds while three moments cross over, and a rail draws the level for each |
| Behaviors (pan) | Breadth | Three cards travel sideways, so the choices read as options rather than steps |
| Privacy | Relief | A dark band, no motion, four plain guarantees |
| Verification | Trust | Real executed/not-executed lists, the count of tests ticking to its true value |
| Close | Resolve | The download, held still, with the character waiting next to it |

**Peak:** the pinned conversation. It gets the most scroll room (3.2 viewports), it is the only act
where the page stops, and it is the only place the app's actual behaviour is shown rather than
described.

## Score

| Beat | Device | Why |
| --- | --- | --- |
| Hero | `flow` + `parallax` + `magnet` | The light and the two readout cards sit on separate planes; the character does not |
| Conversation | `pin` + `cue` | The argument advances while the frame holds, which is what a conversation does |
| Behaviors | `pan` | Lateral travel reads as options; vertical would read as steps |
| Privacy / verification / FAQ | `flow` + `in` + `stagger` + `count` | Ordinary sections, revealed once, never re-hidden |
| Close | `flow` + `in` | Resolves and holds; it is deliberately not a pinned act, so nothing fades it out |

Four device families, no family twice in a row, no scrub clip anywhere (there is no footage).

## Signature move: the conversation rail

`site/landing.js` reads the `--sc-p` the engine publishes on the act and drives a small rail: an AI
level that falls as you travel, an Apple Music level that comes back at the end, and a playhead that
is literally the scroll position. The three chips scroll to the moment they name, and their pressed
state follows the scroll.

It is bespoke to this page, it is built from the product's own two states, and it does not require
the character to move. Vincent holds one frame from top to bottom of the page: no keyframes, no
frame animation, no parallax on the sprite. That was an explicit instruction and it is checked in
`docs/test-evidence.md`.

## Engine

`site/scrollcraft.js` and `site/scrollcraft.css` are the vendor engine, copied unedited from
`plugins/nateherk-design/skills/scroll-craft/engine/` (MIT). Both are committed because the site has
no build step and must work from disk. Never edit them per project: theme through the `--sc-*`
tokens in `styles.css`, which the brand block at the end of that file overrides.

Without JavaScript the page still reads: a `noscript` block lifts every cued element out of its
hidden state and turns both acts back into ordinary stacked sections.

## Verification

See `docs/test-evidence.md` for the recorded runs. What the checks cover: both acts at several
scroll positions on a 1440×900 and a 390×844 viewport, the character's computed transform and
background position at three scroll positions, the rail's measured overflow, horizontal overflow on
mobile, and `prefers-reduced-motion: reduce`.

A four-width audit (375, 768, 1024, 1440) found one defect that the desktop shots hid: on a phone the
rail's heading left the screen after one flick, so the section read as orphaned cards. Below 900px
the pan act therefore stops pinning (`height: auto` on the act, `position: static` on the stage) and
the track becomes a native horizontal scroller with snap points and `scroll-padding-inline`. The
heading always stays at the start, every card is reachable, and the act can no longer spend four
viewports of scroll on a stage that does not move. Measured after the fix: 375 wide, stage
`scrollWidth` 1502 against 375 client, page overflow 0.

What they do not cover: a real iPhone, Safari, and the scroll-craft screenshot harness
(`shoot.mjs`), which was not run here because it needs `playwright-core` installed in the build
folder. The page was inspected in Chrome through ego-browser instead.
