# Brand

Oreja de Van Gogh is a small, local utility. The brand is small and local too: warm paper, warm
black, one indigo, one wheat. No illustration of a robot, no gradient headline, no promise the app
cannot keep.

Everything here is implemented in three places and they must stay in step:

| Where | What it carries |
| --- | --- |
| `apps/macos/Theme.swift` | Palette, metrics, type scale, mark, quiet rows |
| `site/styles.css` | The same tokens as CSS custom properties |
| `tools/IconBuilder/main.swift` | The app icon, drawn from the mark geometry |
| `site/assets/mark.svg` | The canonical mark |

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

## Mark

The listening mark is a filled dot with two waves opening to the right. It works because it is made
of four primitives and survives a 16pt menu bar.

- Inner wave: cream. Outer wave: wheat. Dot: cream.
- On indigo for the app icon; on paper for print or a single-colour lockup (use ink for all three
  shapes, then).
- Clear space: half the mark's width on every side.
- Minimum size: 16pt for the icon; 20pt for the mark on its own.
- Never rotate it, gradient the strokes, outline the dot, add a third wave, or place it on a photo.

`site/assets/mark.svg` is canonical. The app draws the same geometry in `ListeningMark`, and the
icon generator draws it in Core Graphics. If the mark changes, all three change together.

## Wordmark

Live text, never a traced image: `oreja` in a tight semibold lowercase, then `DE VAN GOGH` in small
tracked capitals in the soft ink. On paper, the whole lockup is ink; on indigo, cream.

- Track the short name to about `-0.02em`; track the suffix to about `+0.09em`.
- The suffix is never bolder or larger than the short name.
- Do not set the wordmark in a serif, italic, or all caps.

## Palette

| Token | Light | Dark (app) | Use |
| --- | --- | --- | --- |
| `paper` | `#F7F2E8` | `#11100E` | Page and window wash |
| `card` | `#FFFCF4` | `#1B1916` | Cards, grouped rows |
| `card-muted` | `#F1EADA` | `#17150F` | Hover, quiet fills |
| `ink` | `#14120E` | `#F3EEE2` | Primary text |
| `ink-soft` | `#6C6559` | `#A8A091` | Secondary text, captions |
| `hairline` | `#E1D7C4` | `#2C2823` | Borders, dividers |
| `accent` | `#242C5A` | `#B9C0F0` | Focus, links, speaking state |
| `accent-wash` | `#E9E6F3` | `#232841` | Selected rows |
| `wheat` | `#8A6318` | `#E7B44C` | Quiet highlights, pause held |
| `wheat-bright` | `#E7B44C` | `#E7B44C` | Non-text accents on indigo |
| `positive` | `#4C6A51` | `#9CC2A3` | Verified, playing |
| `warning` | `#A9502C` | `#E8A183` | Errors, missing permission |
| `indigo` | `#242C5A` | `#242C5A` | Mark and icon field |
| `indigo-deep` | `#171D3F` | `#171D3F` | Dark bands, icon gradient |

Rules:

- **One accent per screen.** Indigo is the working accent; wheat marks a held pause or a verified
  step and is never used for a warning.
- Wheat and warning are text colours only at the light values above. `#E7B44C` never carries text on
  paper; it is for the icon, arcs, and one large display detail.
- No colour alone carries meaning: pair every status colour with a word or a glyph.
- No gradients on text, buttons, or surfaces except the icon field. No drop shadows except the
  single product mock on the landing page.

## Typography

System fonts only. The app must build without network access and the site must load without a
third-party font request.

- Display and UI: the system sans (`SF Pro` on macOS). Headlines at `-0.03em` to `-0.045em`
  tracking, weight 600.
- Body: system sans, 12.5–17px, line height 1.55–1.65.
- Labels and measurements: system monospace, 9.5–11px, uppercase with `+0.12em` tracking for
  eyebrows.
- One serif italic per page at most, for a single pull quote. Never for UI.

Scale used by the site: 11 (eyebrow), 14 (caption), 17 (body), 21 (lead), 28 (section), 44–92
(display, fluid). The app uses 10, 11, 12.5, 14, 25.

## Space, shape, motion

- Spacing scale: 4, 8, 12, 16, 24, 32, 48, 64, 96, 128.
- Radii: 8 (controls), 12 (cards, panel), 18 (device), 999 (pills).
- Borders: 1px hairline. Prefer a line to a shadow.
- Motion: 160–260ms, ease-out, one element at a time. No bounce, no parallax. Honour
  `prefers-reduced-motion` and `accessibilityReduceMotion`.

## Surfaces

**Menu bar panel.** One status, one switch, one music line, four quiet rows. The status dot leads;
the toggle sits in the header; the only filled button in the panel appears when Oreja holds a pause
("Resume music now").

**Onboarding.** One idea per page, one primary button, a two-pixel progress line. Never more than
one filled button per page.

**Settings and diagnostics.** Eyebrow, card, rows separated by hairlines. Numerals in monospace.
Diagnostics is dense but never decorative.

**Landing.** Generous whitespace, one product mock, one dark band. Every claim links to evidence or
is softened to what was measured.

## Do not

- Do not add a second illustration style, a mascot, or stock photography.
- Do not use the app icon as a decorative bullet; it is the icon.
- Do not lowercase the full name in running text.
- Do not promise a live ChatGPT Voice test, notarization, or measured latency that is not in
  `docs/test-evidence.md`.
- Do not ship copy in Spanish and English mixed on one surface. The product and its docs are in
  English; translate a whole surface or leave it out.
