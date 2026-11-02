# UI reference: HeyTaby

Reference URL: https://www.heytaby.com/ (observed 1 November 2026)

## Method

No source repository was supplied, so this is a live-artifact review of the shipped page: the rendered
DOM, the two stylesheets it links, its copy order, and the interaction model. Nothing was decompiled
and no asset was reused. The point is to learn the *structure* of the experience, not to copy the
identity.

## Why it is useful for Oreja

HeyTaby makes the product feel present before asking the visitor to understand the architecture. The
first viewport is a character, not a diagram. The rest of the page keeps demonstrating instead of
claiming.

## Observed structure

- **Floating nav:** short wordmark, five plain links, one filled pill action.
- **Hero:** one character as the dominant object, a three-word-to-a-line headline, one sentence of
  copy, a free/no-account promise, one primary action and one "see what it can do" secondary.
- **Proof by demonstration:** small cards that show the product *doing* something — Wi-Fi off, a
  schedule answer, an inbox summary, languages, "tap to talk" — each with a concrete artefact rather
  than an adjective.
- **Interactive section:** "pick one and watch" chips that swap a demo, with one short caption.
- **Trust band:** a wall of short quotes from named users.
- **Closing:** the same download action, a compatibility question, FAQ.
- **Material:** warm cream page, near-black surfaces, generous radii, dense small-type cards.

## Translation for Oreja

| Reference quality | Oreja's own version |
| --- | --- |
| Character dominates the first viewport | Vincent, a generated four-frame pixel painter in a straw hat with a bandaged ear; idle blinks, listening lights the working ear and adds sound marks |
| Proof by demonstration | Two floating cards in the hero (AI speaking, Music at 12%) and a three-scene demo: AI speaks, you answer, it goes quiet |
| "Pick one and watch" | Three pill chips, one stage, one caption — `site/landing.js`, no framework |
| Trust band | Verification cards: what was executed, what was not. Oreja has no users to quote, so it shows evidence instead of testimonials |
| Warm material | Warm white paper, charcoal ink, apricot character, coral light, black pill actions, dark privacy band |
| Local/private promise | The dark band states "It measures a level, not a conversation" and lists the four concrete guarantees |

## What was deliberately not borrowed

- Taby's character, logo, illustrations, screenshots, layout geometry, section order, copy, font
  choice by name, or any raster asset.
- The testimonial wall: inventing quotes would break the evidence rule in `docs/brand.md`.
- Claims Oreja cannot support (measured battery impact, notarization, a live ChatGPT Voice test).

## Boundaries

This is a directional reference. Oreja keeps its own name, listening mark, apricot/coral palette,
GPL license, independent-project disclosure, and its own character. The reference is recorded here so
the intention survives the next redesign.
