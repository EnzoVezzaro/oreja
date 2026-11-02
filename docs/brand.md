# Brand

Oreja de Van Gogh is a small, local utility. The brand is small and local too: warm paper, warm
black, apricot for the companion, coral for the listening light. One character, no robot, no gradient
headline, no promise the app cannot keep.

Everything here is implemented in three places and they must stay in step:

| Where | What it carries |
| --- | --- |
| `apps/macos/Theme.swift` | Palette, metrics, type scale, mark, quiet rows |
| `site/styles.css` | The same tokens as CSS custom properties |
| `tools/IconBuilder/main.swift` | The app icon, cropped from the same sprite sheet |
| `site/assets/mark.png` | The canonical mark: Vincent's head on the paper tile |
| `scripts/vincent-sprite.py` | Vincent's four-frame pixel sprite, shared by the site and the app |

## Name

- **Full name:** Oreja de Van Gogh. First mention, bundle display name, marketing titles.
- **Short name:** Oreja. Interface, wordmark, everything after the first mention.
- **Never:** "Oreja Van Gogh", "the Oreja", "ODVG", "Oreja.ai", or an invented product line.

The name is a reference to the ear, not a claim on the painter or his estate. The app is independent
and must never imply affiliation with OpenAI or Apple.

## One line

**Your AI talks. Your music listens.**

Use it as a tagline, never as a heading on its own. Supporting sentence: *Oreja pauses Apple Music
while ChatGPT speaks and resumes it when the reply ends.*

## Voice

Plain, specific, unhurried. It sounds like a careful person explaining a small tool, not a launch
post. Short sentences. Active voice. No exclamation marks, no emoji in product copy, no "magic",
"seamless", "supercharge", "unleash", "effortless".

| Write this | Not this |
| --- | --- |
| Pauses music while ChatGPT speaks. | Intelligently orchestrates your audio experience. |
| It listens to the app's output, not your microphone. | Advanced AI-powered listening. |
| Not yet measured against a live Voice session. | Fully tested in real conversations. |
| Your music resumes where it left off. | Never lose your flow again. |

Rules that outrank tone:

1. State only what was observed. If a test was not run, say so. `docs/test-evidence.md` is the source
   of truth for claims.
2. Name the limitation next to the benefit, not in a footnote.
3. Never call activity detection "speech recognition". The app measures output level.
4. Local, no account, no API key, no recording: say it once per page, plainly, and move on.

## Logo

The logo is Vincent's head: straw hat, cream bandage, rust beard, on an apricot-wash tile with a 26%
continuous radius. Not a monogram, not a wave, not a spiral — the character carries the name, and he
is the only drawing in the product, so he is also the thing people recognise in a Dock and a menu bar
panel.

- Tile: `accent-wash` (`#FDE7D5`). Crop: frame 0 of `oreja-vincent.png` at (26, 8, 268 × 308) of its
  320-point frame, filling 76% of the tile.
- Sizes: 38 px in the site header, 32 px in the menu bar panel, 36 px in settings, 24 px on
  onboarding, 16–1024 px in the icon. Integer multiples of the 40 px grid where it is larger than
  40 px, so pixels stay square.
- Clear space: half the mark's width on every side. On dark surfaces the tile is its own ground; the
  mark never inverts and is never placed directly on a photo.
- Minimum size: 16 px. At that size the hat outline and the beard are the whole read, which is why
  the crop is tighter than the full sprite.
- Never rotate it, recolor the tile, crop below the collar, or add a second character beside it. The
  sprite is redrawn in `scripts/vincent-sprite.py` only; a mask or a redraw in another style would
  drift the three surfaces apart.

`site/assets/mark.png` (320 px) and `mark-128.png` (favicon) are rendered from `BrandMark` itself, so
the header, the panel and the icon are the same crop of the same sheet rather than three drawings
that resemble each other. `tools/IconBuilder` reproduces that crop on the Big Sur icon grid. Recrop
once, recrop everywhere — and regenerate the two PNGs when the sprite changes:

```bash
python3 scripts/vincent-sprite.py     # sprite
# then re-render BrandMark to site/assets/mark.png and mark-128.png, and ./scripts/build.sh for the icon
```

## Vincent

Vincent is the one illustration in the product: a small pixel painter in a straw hat and a rust
beard, with a cream bandage over the ear he gave away and a listening ear on the other side. He is a
character, not a portrait and not a likeness of any painted self-portrait: a hat, a beard, a bandage
and a coat are enough to read the name, and the name is the joke — one ear is still listening.

- The sprite is a 40×40 grid, five frames wide: idle, idle blink, listening, listening blink, ouch.
  The ouch frame is the click joke: the bandage leaves his head, his eyes shut and he shouts.
- Generate it with `python3 scripts/vincent-sprite.py`; never draw frames by hand or in a second
  style. The same PNG ships in the app bundle and on the website.
- Display it at an integer multiple of the grid (40, 80, 120, 160, 200 px) so pixels stay square.
- Vincent reacts to real state. Listening means the AI source is active; the app blinks on a slow
  timer so he is alive without moving constantly. He never appears in a place where he would suggest
  a feature that does not exist.
- He does not float, bob, drift or parallax, on the website or in the app. He blinks in place and
  plays the ouch frame when clicked; the only movement allowed is a two-pixel shake during that
  click. Pixel art stays on whole pixels, so no rotation or fractional offset.
- Minimum size: 40px. Do not rotate, recolor, blur, or add props to him. The hat, bandage, beard
  and coat are fixed; a brush, a pipe, an easel or a headphone cup would crowd a 40px grid.
- Illustration colours live in the generator, not in the UI palette: straw `#E7B44C`, beard
  `#B4502F`, bandage `#FFF6EC`, coat `#33506F`, ear `#E77952`. They are the one cool family in an
  otherwise warm interface, and they stay inside the sprite.

## Wordmark

Live text, never a traced image: `oreja` in a tight semibold lowercase, then `DE VAN GOGH` in small
tracked capitals in the soft ink. On paper, the whole lockup is ink; on indigo, cream.

- Track the short name to about `-0.02em`; track the suffix to about `+0.09em`.
- The suffix is never bolder or larger than the short name.
- Do not set the wordmark in a serif, italic, or all caps.

## Palette

| Token | Light | Dark (app) | Use |
| --- | --- | --- | --- |
| `paper` | `#FBF7F0` | `#16130F` | Page and window wash |
| `card` | `#FFFDFA` | `#221E19` | Cards, grouped rows |
| `card-muted` | `#F8F0E4` | `#1B1713` | Hover, quiet fills |
| `ink` | `#24211D` | `#F7F1E6` | Primary text, primary button |
| `ink-soft` | `#6F675C` | `#B0A696` | Secondary text, captions |
| `hairline` | `#E8DFD2` | `#322C25` | Borders, dividers |
| `accent` | `#A7472A` | `#F3A88E` | Focus, links, controls |
| `accent-wash` | `#FDE7D5` | `#33241C` | Selected rows, mark tile |
| `coral` | `#E77952` | `#EF8A5F` | Listening light, Vincent's inner ear |
| `apricot` | `#F8C39B` | `#E8A97F` | Vincent's body, scene glow |
| `positive` | `#4C6A51` | `#9CC2A3` | Verified, playing |
| `warning` | `#A9502C` | `#E8A183` | Errors, missing permission |

Rules:

- **One accent per screen.** Coral is the working accent; apricot is material, not a status colour.
- Buttons are pills. The primary action is ink with paper text, or paper with ink text inside the
dark band; there is never more than one filled primary per surface.
- No colour alone carries meaning: pair every status colour with a word or a glyph.
- No gradients on text or buttons. The only soft gradients are the scene glow behind Vincent and the
  warm wash inside the download card.

## Typography

The app uses the system sans and must build without network access. The site self-hosts one font
from the same folder and makes no third-party request.

- Display and UI, site: Manrope (variable), `assets/fonts/manrope-variable.ttf`, OFL, weight 800 for
  display with `-0.05em` tracking and 1.0 line height.
- Display and UI, app: the system sans (`SF Pro` on macOS). Headlines at `-0.03em` to `-0.045em`
  tracking, weight 600.
- Body: 12.5–17px, line height 1.55–1.65.
- Labels and measurements: monospace, 9.5–11px, uppercase with `+0.12em` tracking for eyebrows.

Scale used by the site: 11.5 (eyebrow), 13 (caption), 16.5 (body), 16.5 (lead), 30–44 (section),
42–78 (display, fluid). The app uses 10, 11, 12.5, 14, 25.

## Space, shape, motion

- Spacing scale: 4, 8, 12, 16, 24, 32, 48, 64, 96, 128.
- Radii: 9 (controls), 18 (cards, panel), 22 (stage), 30–36 (large surfaces), 999 (pills).
- Borders: 1px hairline. Prefer a line to a shadow; the soft shadow belongs to floating cards.
- Motion: 160–260ms for interface, 1.8–5.6s for Vincent and the glow. One element at a time, no
  bounce, no parallax. Honour `prefers-reduced-motion` and `accessibilityReduceMotion`; with reduced
  motion Vincent holds a single frame and every state stays readable in text.

## Surfaces

**Menu bar panel.** One status, one switch, one music line, four quiet rows. The status dot leads;
the toggle sits in the header; the only filled button in the panel appears when Oreja holds a pause
("Resume music now").

**Onboarding.** One idea per page, one primary button, a two-pixel progress line. Never more than
one filled button per page.

**Settings and diagnostics.** Eyebrow, card, rows separated by hairlines. Numerals in monospace.
Diagnostics is dense but never decorative.

**Landing.** A floating pill nav, a short centred headline, one big character, two floating status
cards, one interactive three-scene demo, three feature cards, one dark privacy band, the evidence
cards, one download card and the FAQ. Every claim links to evidence or is softened to what was
measured.

## Do not

- Do not add a second illustration style, a second mascot, or stock photography. Vincent is the only
  character and he is generated by one script.
- Do not use the app icon as a decorative bullet; it is the icon.
- Do not lowercase the full name in running text.
- Do not promise a live ChatGPT Voice test, notarization, or measured latency that is not in
  `docs/test-evidence.md`.
- Do not ship copy in Spanish and English mixed on one surface. The product and its docs are in
  English; translate a whole surface or leave it out.
