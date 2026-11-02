# Site

The landing page and the documentation page for Oreja de Van Gogh. Static HTML and CSS, no build
step, no framework, no third-party requests. It renders from disk and offline.

```
site/
  index.html        landing page (the painted night)
  docs.html         documentation (setup, permissions, states, troubleshooting, privacy)
  styles.css        design system for the documentation page
  night.css         the landing page: palette, painted hero, act, dawn, phone layout
  scrollcraft.css   vendor scroll engine stylesheet (copied unedited, MIT)
  scrollcraft.js    vendor scroll engine (copied unedited, MIT)
  landing.js        mounts the engine, paints the waveform, star field and click joke
  assets/mark.png   the brand mark: Vincent's head, rendered from the app's BrandMark
  assets/mark-128.png  the same mark at favicon size
  assets/night-sky.png, night-hills.png, night-front.png   the painting, generated
  assets/oreja-vincent.png   Vincent's five-frame pixel sprite
  assets/vincent-desk.png, vincent-back.png   two further poses, generated
  assets/fonts/     Manrope variable + Instrument Serif italic/regular (OFL)
```

The sky, hills, foreground and the extra poses come from `scripts/night-scene.py` and
`scripts/vincent-scenes.py`; do not hand-edit those PNGs.

## The painted hero

The first screen is a painted night: one image, four animated copies. A base layer breathes and
drifts, three further copies are masked to a single current each (the two spirals and the low cloud
river) and move against it on clocks of 41 s, 57 s and 68 s, and a broad moonlight band crosses the
clouds every 38 s. All four animate transform and opacity only, so the compositor does the work;
`prefers-reduced-motion: reduce` stops them at their first frame. Stars, embers and the occasional
shooting star are drawn on a canvas above the paint.

One trap, found by measurement and recorded here so it is not reintroduced: an animated child that
stays inside `.n-sky` makes Chrome drop the masked group's backdrop, and the whole painting
(normally ~0.36 mean luminance) renders as flat `#080a20`. The moonlight band therefore lives outside
`.n-sky`, as a sibling in the hero, and it uses plain alpha rather than a blend mode.

On phones (≤820 px) the hero becomes a two-column grid — copy across both columns, then the sprite
and the readout side by side — so no viewport height or text length can stack one element on top of
another. It previously did: at 390 px the readout overlapped the facts line and the sprite.

Vincent is generated from `scripts/vincent-sprite.py`; do not hand-edit the PNG. The sprite is five
40×40 frames wide (idle, idle blink, listening, listening blink, ouch) and the CSS addresses frames
by `background-position` percentages over a 500% background; the site uses the first four, and the
fifth is the click joke in the app. The macOS app ships the same file, so a change here must be
regenerated and rebuilt, not edited in two places.

The site pins Vincent to the first frame. He does not blink, bob, float or parallax, on scroll or
otherwise: the frame animation was removed because it read as the character scrolling. Frames stay
in the app, where they mark a state the user just triggered. `scripts/vincent-sprite.py --preview 2`
writes `build/vincent-preview.png` at the 80 px size the sprite has to read at.

The landing page is scroll-driven through the [scroll-craft](https://github.com/nateherkai/scroll-craft)
engine: a pinned conversation act, a lateral behaviors rail, and flow reveals. `docs/scroll-craft.md`
records the brief, the chosen grammar and the signature move. The two `scrollcraft.*` files are the
vendor engine and are never edited here; theme through the `--sc-*` tokens at the end of
`styles.css`.

## Preview

Production: **https://oreja-tau.vercel.app** — Vercel project `oreja`, connected to
`EnzoVezzaro/oreja` with this folder (`site/`) as the project root directory. Pushes to `main`
deploy it automatically. A manual deploy is also available with
`vercel deploy site --prod --yes --project oreja`.

Open `site/index.html` directly, or serve the folder so relative links behave like a real site:

```bash
python3 -m http.server 8000 -d site
# http://localhost:8000
```

## Deploy pipeline

Vercel's Git integration owns the deploy; GitHub Actions owns the check.

| Setting | Value |
| --- | --- |
| Repository | `EnzoVezzaro/oreja` |
| Production branch | `main` |
| Root directory | `site` |
| Framework | Other (static output; no `package.json`, so no build or install runs) |
| Ignored Build Step | `git diff HEAD^ HEAD --quiet -- .` — build only when `site/` changed |
| Deployment Checks | GitHub check `check` on the same commit must pass before production is aliased |

On a push to `main` that touches `site/`, Vercel publishes production. Pull requests and other
branches get preview deployments. Pushes that only change the macOS app, packages, docs, or
workflows are skipped before a build starts; Vercel may list the skipped attempt as canceled.

The custom step is required because Vercel's automatic skip only supports npm, yarn, pnpm, or Bun
workspaces, and this repository is Swift. With `site` as the root directory, `git diff HEAD^ HEAD
--quiet -- .` exits 0 when nothing under `site/` changed, which tells Vercel to skip the build.

`.github/workflows/site.yml` runs `scripts/check-site.py` for every change under `site/` and on
pull requests. The check fails on unbalanced HTML, duplicate ids, broken internal links, undefined
anchors, external assets, or unbalanced CSS. It deliberately does not deploy: a second deploy path
would race the Vercel integration.

The workflow's `check` job is imported as a Vercel Deployment Check for production. Vercel builds
the deployment, then aliases it to the production domain only after that GitHub check passes. A
failed or missing check leaves the previous production deployment serving traffic. Renaming the job
requires updating the Deployment Check in Vercel, because Vercel matches the check run name.

```bash
python3 scripts/check-site.py   # same check the CI job runs
```

Vercel builds a deployment for every push that touches `site/`, then aliases it to production only
after the `check` Deployment Check passes.

## Rules

- Tokens in `styles.css` mirror `apps/macos/Theme.swift` and `docs/brand.md`. Change them together.
- The mark is one raster: `assets/mark.png` and `assets/mark-128.png`, rendered from `BrandMark` in
  `apps/macos/Theme.swift` and referenced by `<img class="n-mark">` / `.mark-tile` in both pages. If
  the sprite changes, re-render both PNGs and rebuild the icon; never draw a second mark.
- No external fonts, analytics, images or scripts. Manrope is self-hosted from `assets/fonts/`, and
  the only raster asset is Vincent's generated sprite. His caption is real text, not an image.
- Copy states only what `docs/test-evidence.md` supports: what was executed, and what was not.
- The deployed folder must be self-contained: every `href` resolves inside `site/` or is an explicit
  external URL. Repository Markdown is referred to by filename (`docs/privacy.md`), not linked,
  because it lives outside the deployed root and would 404 in production.
