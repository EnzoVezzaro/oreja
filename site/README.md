# Site

The landing page and the documentation page for Oreja de Van Gogh. Static HTML and CSS, no build
step, no framework, no third-party requests. It renders from disk and offline.

```
site/
  index.html        landing page
  docs.html         documentation (setup, permissions, states, troubleshooting, privacy)
  styles.css        the whole design system, shared by both pages
  assets/mark.svg   canonical brand mark
```

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
| Skip deployments | Enabled when nothing under `site/` changed |

On a push to `main` that touches `site/`, Vercel publishes production. Pull requests and other
branches get preview deployments. Pushes that only change the macOS app, packages, or docs are
skipped, so they cannot break the site deployment.

`.github/workflows/site.yml` runs `scripts/check-site.py` for every change under `site/` and on
pull requests. The check fails on unbalanced HTML, duplicate ids, broken internal links, undefined
anchors, external assets, or unbalanced CSS. It deliberately does not deploy: a second deploy path
would race the Vercel integration.

```bash
python3 scripts/check-site.py   # same check the CI job runs
```

Automatic deploy only works once `site/` is committed to `main`. Until then the remote has no site
to publish.

## Rules

- Tokens in `styles.css` mirror `apps/macos/Theme.swift` and `docs/brand.md`. Change them together.
- The mark geometry is duplicated as an inline `<symbol id="mark-tile">` in both pages. If
  `assets/mark.svg` changes, change both symbols and `apps/macos/Theme.swift` (`ListeningMark`).
- No external fonts, analytics, images or scripts. The product mock is CSS, not a screenshot, and
  its caption says so.
- Copy states only what `docs/test-evidence.md` supports. Keep the "Not yet" list honest when a test
  is finally run, and move the item rather than deleting the section.
- The deployed folder must be self-contained: every `href` resolves inside `site/` or is an explicit
  external URL. Repository Markdown is referred to by filename (`docs/privacy.md`), not linked,
  because it lives outside the deployed root and would 404 in production.
