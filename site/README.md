# Site

The landing page and the documentation page for Oreja de Van Gogh. Static HTML and CSS, no build
step, no framework, no third-party requests. It renders from disk and offline.

```
site/
  index.html        landing page
  docs.html         documentation (setup, permissions, states, troubleshooting, privacy)
  styles.css        the whole design system, shared by both pages
  scrollcraft.css   vendor scroll engine stylesheet (copied unedited, MIT)
  scrollcraft.js    vendor scroll engine (copied unedited, MIT)
  landing.js        mounts the engine, then drives the pinned act and its rail
  assets/mark.svg   canonical brand mark
  assets/oreja-vincent.png   Vincent's four-frame pixel sprite
  assets/fonts/manrope-variable.ttf   the one self-hosted font (OFL)
```

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
- The mark geometry is duplicated as an inline `<symbol id="mark-tile">` in both pages. If
  `assets/mark.svg` changes, change both symbols and `apps/macos/Theme.swift` (`ListeningMark`).
- No external fonts, analytics, images or scripts. Manrope is self-hosted from `assets/fonts/`, and
  the only raster asset is Vincent's generated sprite. His caption is real text, not an image.
- Copy states only what `docs/test-evidence.md` supports. Keep the "Not yet" list honest when a test
  is finally run, and move the item rather than deleting the section.
- The deployed folder must be self-contained: every `href` resolves inside `site/` or is an explicit
  external URL. Repository Markdown is referred to by filename (`docs/privacy.md`), not linked,
  because it lives outside the deployed root and would 404 in production.
