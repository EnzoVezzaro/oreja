# Design tokens (measured)

Canonical reference for the website. Every value here was read from the live computed styles of
`site/index.html` at 1440×900, not copied from memory, so it is what the browser actually applies.
Treat it as the source of truth: a new value that is not in this file needs a reason in the commit.

Source of truth for the values themselves is `site/styles.css` (`:root`) and
`apps/macos/Theme.swift`. This file records what those resolve to.

## Colour

| Role | Token | Value | Use |
| --- | --- | --- | --- |
| Page ground | `--paper` | `#fbf7f0` | body, act grounds |
| Deep ground | `--paper-deep` | `#f4ebdf` | washes, nested surfaces |
| Card | `--card` | `#fffdfa` | the pinned frame, rail cards |
| Muted card | `--card-muted` | `#f8f0e4` | art wells, meter tracks, the closing note |
| Ink | `--ink` | `#24211d` | headings, primary text |
| Soft ink | `--ink-soft` | `#6f675c` | body copy, labels, secondary rows |
| Hairline | `--line` | `#e8dfd2` | borders, dividers |
| Strong hairline | `--line-strong` | `#d8cbb8` | hover borders, rail ticks, scrollbar thumb |
| Apricot | `--apricot` | `#f8c39b` | the wash behind the character |
| Apricot soft | `--apricot-soft` | `#fde7d5` | the mark tile |
| Coral | `--coral` | `#e77952` | decoration only, 2.71:1 on paper |
| Coral deep | `--coral-deep` | `#c95f3c` | text at 24px and above, 3.79:1 |
| Coral ink | `--coral-ink` | `#a7472a` | small text and focus rings, 5.5:1 |
| Action | `--accent` | `#24211d` | filled buttons |
| Band | `--band` | `#221f1b` | the privacy chapter |
| Band ink | `--band-ink` | `#f7f1e6` | text on the band |

Dark mode redefines the same names in a `prefers-color-scheme: dark` block. Never introduce a
second accent: coral owns one region, at one of three fixed weights.

## Type

One family, Manrope variable, self-hosted; the system mono for timings and versions. Measured at
1440 wide:

| Role | Size | Weight | Line height | Tracking |
| --- | --- | --- | --- | --- |
| Display `h1` | 78px (fluid 42–78) | 800 | 0.96 | -0.05em |
| Section `h2` | 42px (fluid 30–44) | 800 | 1.06 | -0.045em |
| Act `h3` | 31px (fluid 23–31) | 800 | 1.1 | -0.04em |
| Lead | 15.5px | 400 | 1.6 | -0.005em |
| Body | 15px | 400 | 1.62 | -0.005em |
| Mono detail | 12px (`--mono`) | 400 | 1.62 | -0.005em |
| Chip | 13.5px | 700 | 1.62 | normal |

Tracking tightens as size grows (that is optical correction, not decoration). Body copy stays under
a 62ch measure.

## Shape and elevation

| Thing | Value |
| --- | --- |
| Standard radius | 22px (`--radius`) |
| Large surface radius | 30px (`--radius-lg`) |
| Small surface (rail readout) | 18px |
| Pills, chips, meters | 999px |
| Card shadow | `0 26px 60px -40px rgba(63, 43, 26, 0.55)` |
| Lifted shadow | `0 30px 70px -42px rgba(63, 43, 26, 0.6)` |

Prefer a hairline to a shadow. Depth comes from offset and blur, never from a zero-offset glow.

## Space

- Gutter: `clamp(18px, 4vw, 40px)`. Content width: `1080px`.
- Section rhythm: `clamp(64px, 9vw, 108px)` top, plus the pinned stage's own viewport of travel.
- Scale in use: 4, 8, 12, 16, 24, 32, 48, 64, 96, 128.

## Motion

| Token | Value |
| --- | --- |
| `--ease-out` | `cubic-bezier(0.23, 1, 0.32, 1)` |
| `--ease-in-out` | `cubic-bezier(0.77, 0, 0.175, 1)` |
| `--dur-fast` | 140ms |
| `--dur-ui` | 200ms |
| Flow reveal | 620ms, 14px rise, 45–90ms stagger |
| Pointer devices | tilt 5–9deg, magnet 0.22–0.35 |

Only `transform`, `opacity` and `clip-path` animate. Every motion respects
`prefers-reduced-motion: reduce`, and the character has no animation at all.

## Engine bridge

`scrollcraft.css` ships its own six colour tokens and two font tokens; the brand overrides them at
the end of `styles.css`:

| Engine token | Brand token | Resolves to |
| --- | --- | --- |
| `--sc-canvas` | `--paper` | `#fbf7f0` |
| `--sc-ink` | `--ink` | `#24211d` |
| `--sc-ink-soft` | `--ink-soft` | `#6f675c` |
| `--sc-accent` | `--coral-deep` | `#c95f3c` |
| `--sc-surface` | `--card` | `#fffdfa` |
| `--sc-accent-ink` | `--paper` | `#fbf7f0` |
| `--sc-font-display`, `--sc-font-text` | `--sans` | Manrope |
| `--sc-font-mono` | `--mono` | system mono |

## Viewport checks

Measured after the scroll rewrite, at 375×812, 768×1024, 1024×768 and 1440×900: no horizontal page
overflow at any width, no clipped text node, the pinned stage's content fits its viewport at every
width, and the behaviors rail travels (568px of overflow at 1440). Below 900px the rail stops
pinning and becomes a native swipe strip with snap points, so the act cannot become dead scroll on
a phone.
