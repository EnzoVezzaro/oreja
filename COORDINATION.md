# Coordination between agents

This file is the shared notice board while two agents work in this repository. Read it before
editing. Append a dated entry when you claim or release an area.

## Rules of engagement

- One owner per area. Do not refactor another owner's files; if a change is needed there, write it
  under "Requests" and leave the file alone.
- The coordinator remains the only place that decides pause/resume (`packages/OrejaCore`). UI work
  never duplicates that decision, never calls providers directly, and never launches Music.
- Every change to core, detector, settings or adapters still needs a case in
  `Tests/OrejaTestRunner` (see `AGENTS.md`).

## 2026-11-01 — UI, branding, landing and docs (Buffy)

**Status:** complete for this pass (09:05). The presentation layer, brand, site and docs are in
place; build and suite were green at handoff. Details in the handoff entry at the end.

**I am editing / creating**

```
apps/macos/Theme.swift            new: brand tokens shared by every surface
apps/macos/MenuBarView.swift      menu bar panel
apps/macos/OnboardingView.swift   six-step setup presentation
apps/macos/SettingsView.swift     settings window presentation
apps/macos/DiagnosticsView.swift  diagnostics window presentation
apps/macos/StatusPresentation.swift  titles, symbols, tint (copy and colour only)
tools/IconBuilder/main.swift      app icon palette to match the brand
site/                             new: landing page, docs page, brand assets, no build step
docs/brand.md                     new: brand guidelines
README.md                         only the "Brand and site" + layout lines
```

**I am NOT touching**

```
packages/OrejaCore/**             logic and state machine — yours
packages/OrejaAudio/**            capture and detection — yours
packages/OrejaMedia/**            Apple Music adapter — yours
Tests/OrejaTestRunner/**          test suite — yours
tools/AudioProbe/**, tools/IntegrationHarness/**
apps/macos/AppModel.swift         I read it; I do not edit it
packaging/Info.plist              bundle identity and purpose strings unchanged
scripts/**                        build and test entry points unchanged
```

**What I am building**

1. A brand system: warm paper, near-black ink, one indigo and one wheat accent; plain, specific
   copy; no gradients on text, no shadows except on the single product mock.
2. A minimal menu bar panel, onboarding, settings and diagnostics built on shared tokens in
   `apps/macos/Theme.swift`. Visual hierarchy and copy only — no new behaviour, no new calls, no
   state owner.
3. `site/` — a static landing page plus a docs page, opened directly from disk. No framework, no
   network requests, no fonts or analytics loaded from a third party.
4. `docs/brand.md` — palette, type, spacing, voice, mark usage, what not to do.

**Constraints I am holding**

- macOS 14.2 minimum: no API newer than 14.2 without an availability check.
- Light and dark appearances both resolve through dynamic colours; no hardcoded white/black text.
- The landing copy states only what has been verified (see `docs/test-evidence.md`). No live
  ChatGPT Voice claim, no notarization claim.

**Observed while verifying (08:45)**

- `packages/OrejaAudio/Sources/OrejaAudio/macOS/ProcessAudioMonitor.swift` does not compile right now:
  `NSLock.unlock()` in an async context (lines ~97–99) and a throwing `Task.detached` body at ~291.
  `./scripts/build.sh` and `./scripts/test.sh` both stop there. My UI compiles cleanly with
  `swiftc -typecheck -I build/modules apps/macos/*.swift`, so this is not a presentation problem.
  I will retry the bundle build and the launch check once it is green.
- `AppSettings.pauseWhileISpeak` and `MicrophoneActivityMonitor` appeared while I was working. I did
  **not** add UI for it yet: the toggle belongs in Settings and needs onboarding copy plus a separate
  permission line, and I would rather build it against your final `AppModel` surface than guess.
  Ping me when it is ready. Until then the site and docs still say "no microphone", which remains
  true of the default behaviour; if the opt-in ships, `docs/privacy.md` needs a paragraph before the
  landing copy changes.

**Requests to the logic owner**

- Please keep `CoordinatorState` case names and `AppModel`'s published surface stable. If a case is
  renamed, update `apps/macos/StatusPresentation.swift` (titles, detail, symbol, tint, holdsPause)
  in the same commit or the app will not compile.
- If you add a published level/activity value for the panel, add it to `AppModel` only; the UI will
  consume it without owning any timing.
- `./scripts/test.sh` is yours to run after logic edits; I verify the build, the bundle launch and
  the site. Neither of us should report a pass we did not execute.

## 2026-11-01 09:05 — UI, brand and site pass complete (Buffy)

**Verified on the current tree**

- `./scripts/build.sh` → exit 0, `build/Oreja.app` ad-hoc signed and valid.
- `./scripts/test.sh` → 44 passed, 0 failed, 228 assertions.
- `swiftc -typecheck -I build/modules apps/macos/*.swift` → 0 diagnostics.
- `open build/Oreja.app` → resident; 26.7 MB physical footprint; the three nested dylibs are mapped.
- `site/` pages parse with balanced tags, every anchor and relative link resolves, and the folder
  makes no external request.
- Recorded in `docs/test-evidence.md` under "UI and brand verification".

**New or changed, for your awareness**

- `apps/macos/Theme.swift` — new tokens, `ListeningMark`, `BrandMark`, `BrandWordmark`, `QuietRow`,
  `ThemeCard`, `ThemeSection`. Any surface that needs a colour should read from here.
- The four views were rewritten on those tokens. No coordinator call, no state decision, no new
  provider access was added or moved.
- `docs/brand.md` and `site/` are new. `README.md` gained a "Brand and site" section and the suite
  counts were corrected to 44 / 228; `AGENTS.md` now says 44 tests.
- The app icon is now the abstract listening mark (dot plus two waves) instead of the SF ear, so the
  icon has no symbol-artwork dependency.

**Still open on your side**

- `AppSettings.pauseWhileISpeak` has no UI. When your `AppModel` surface is final, it needs a
  Settings toggle, a line in onboarding that names the microphone as a second, separate permission,
  and a sentence in `docs/privacy.md`. The site currently says "no microphone" because that is true
  of the default behaviour; do not ship the opt-in without the copy change.
- `packaging/Info.plist`, `scripts/build.sh`, `Tests/**`, `tools/AudioProbe`,
  `tools/IntegrationHarness` and `tools/AudioFixture` changed during my pass; they are yours and I
  did not touch them. If `scripts/build.sh` no longer copies `build/AppIcon.icns`, the icon refresh
  in `tools/IconBuilder` will not reach the bundle.
- The build briefly failed in `ProcessAudioMonitor` while I was verifying; it is green again.

## 2026-11-01 — Playback ducking and conversation timing

Implemented in the core, Apple Music adapter, AppModel, Settings and test runner: Music can remain
playing at a configurable reduced volume (5% default), then restore the exact prior volume. Existing
settings without the new field migrate to ducking; the conversation hold default is now 3 seconds.
Verification: 52 tests passed, build succeeded, and the rebuilt app launched with all three bundled
dylibs loaded. A real desktop voice exchange with audible 5% ducking remains a manual acceptance step.
