# AGENTS.md

## Purpose

Oreja de Van Gogh is a macOS menu bar utility that pauses Apple Music while any selected audio app speaks and
resumes it after a quiet interval. One job, local only, no OpenAI API, no recording.

## Architecture boundaries

- `packages/OrejaCore` — domain models, ports, `PlaybackCoordinator`, settings, diagnostics.
  **No AppKit, Core Audio, or AppleScript imports.** Everything here must stay platform-neutral and
  deterministic so it can be reused by the iOS companion and tested without hardware.
- `packages/OrejaAudio` — Core Audio process discovery, process taps, level sampling, activity
  detector. Imports CoreAudio; must not import SwiftUI.
- `packages/OrejaMedia` — Music control through Apple Events (`NSAppleScript`) plus a mock provider.
- `apps/macos` — SwiftUI menu bar app, onboarding, settings, diagnostics, AppKit glue. Presentation
  reads coordinator state; it never decides pause/resume.
- `Tests/OrejaTestRunner` — executable test suite (this machine has no XCTest runtime).
- `tools/AudioProbe` — developer-only capture diagnostic. Never ships in the app bundle.

Rules:

1. The coordinator owns pause/resume decisions and pause ownership. Do not duplicate that logic in
   views, adapters, or `AppModel`.
2. Adapters declare capabilities and fail with typed errors; never guess provider state.
3. Never launch the Music app, reset a track, clear a queue, or change volume without an explicit
   user request.
4. The Core Audio IOProc is real-time: no allocation, no blocking locks (the sampler uses
   `trylock` and drops a frame rather than waiting), no UI, no Swift concurrency hops inside it.
   Feed the `LevelSampler` only.
5. Audio samples are never persisted. Diagnostics may record state transitions and thresholds, not
   audio, prompts, responses, or track metadata beyond what the UI needs.

## Build

```bash
./scripts/build.sh            # build/Oreja.app (ad-hoc signed)
./scripts/build.sh --probe    # plus build/bin/oreja-probe
./scripts/build.sh --no-sign
OREJA_SIGN_IDENTITY="Developer ID Application: …" ./scripts/build.sh   # hardened runtime
```

SwiftPM's manifest tooling is broken in this Command Line Tools install; the scripts invoke
`swiftc` directly. `Package.swift` is canonical for full Xcode installations — keep its target
paths in sync when moving files.

## Test

```bash
./scripts/test.sh             # all 83 tests
./scripts/test.sh resume      # name filter
./build/bin/oreja-probe --list
./build/bin/oreja-probe --pid <pid> --seconds 6
./scripts/build.sh --harness  # real tap → coordinator → Apple Music test
```

Add a case to `Tests/OrejaTestRunner` for every coordinator, detector, settings, or adapter change.
A new behavior without a test is incomplete. Run the suite after edits; do not report a pass you did
not execute.

## Coding standards

- Swift 6 language mode, strict concurrency. UI and `AppModel` are `@MainActor`.
- Prefer value types in core; protocols for ports; no singletons except `AppModel.shared` required
  by the AppKit lifecycle.
- Availability-gate every API newer than macOS 14.2 with `@available` / `#available`.
- Small files, focused types, no speculative abstraction, no new dependencies without a concrete
  need.
- User-facing strings are plain, specific, and never claim a success that was not verified.

## Verification requirements

- Automated tests must pass: `./scripts/test.sh`.
- Build must succeed and `build/Oreja.app` must launch: `open build/Oreja.app`, then confirm it
  actually loaded — `pgrep` alone is not enough (a dyld failure leaves a doomed process for a
  moment). Check `vmmap -summary $(pgrep -x Oreja) | grep footprint` is tens of MB and that `lsof`
  shows `Oreja.app/Contents/Frameworks/*.dylib`.
- For audio changes, verify with the probe against a real audio-producing process and state exactly
  what was tested.
- Never claim a real ChatGPT Voice test, real Apple Music control, notarization, or measured latency
  unless it was actually executed and observed. Record evidence in `docs/test-evidence.md`.
- If a permission dialog blocks a test, report it as not executed, not as passed.

## Privacy requirements

No recording, transcription, upload, analytics SDK, account, or remote service. No microphone
access for the default behavior. Process audio locally and discard samples after computing levels.
Do not weaken these properties to make a demo or a distribution step easier.

## Non-goals

- Replacing ChatGPT or building an in-app AI assistant on macOS.
- Recording or transcribing conversations.
- Cross-app audio capture on iOS, or any private API / security bypass.
- Multi-agent orchestration inside the runtime.
- Windows, Android, Linux, or extra music providers (Spotify, VLC, browser tabs) before the macOS
  core is verified end to end. Volume ducking and the microphone "pause while I speak" option are
  shipped and are no longer non-goals.
