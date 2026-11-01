# Roadmap

Order is deliberate: macOS must be reliable before iPhone, and iPhone before other platforms.
Optional platform work does not start until the macOS acceptance criteria pass.

## Milestone 0 — Research (done)

- macOS capability matrix and risk list: `feasibility.md`.
- API choices: Core Audio process taps, Apple Events, `MenuBarExtra`, `SMAppService`.
- Reviewed Apple documentation and community tap implementations; no third-party dependency.
- Verified ChatGPT desktop identity (`com.openai.codex`) on the test machine.

## Milestone 1 — Technical proof (done for capture, partial for the product)

- Target one application's audio processes. ✅
- Monitor output activity with a real tap. ✅ (verified with a controlled process)
- Pause and resume Apple Music. ⏳ implemented, not executed live (Automation consent)
- Demonstrate before polishing the UI. ✅ components and bundle

## Milestone 2 — Core reliability (done in code, tested)

- Explicit coordinator state machine and pause ownership.
- Manual overrides, track changes, process exit, permission loss, device loss, sleep/wake.
- Bounded retries, command failure limit, quit restoration, crash-recovery journal.
- 39 automated tests, including every scenario in the master prompt's list.

Remaining: run the same scenarios against real ChatGPT Voice and real Music, and fix what the real
world breaks.

## Milestone 3 — Native UI (done, needs human click-through)

- Menu bar panel with one state, one switch, and the actions that matter.
- Six-step onboarding with a real connection test.
- Settings (source, provider, resume delay, launch at login, diagnostics verbosity).
- Diagnostics with an in-memory event log and copy action.
- Accessibility labels, reduced-motion-safe design, light/dark appearance.

Remaining: a human walkthrough on a real session, VoiceOver pass, and copy review.

## Milestone 4 — macOS release (not done)

- Developer ID signing and notarization (no credentials here). See `distribution.md`.
- DMG or ZIP, release notes, installation guide, compatibility matrix.
- Gatekeeper test on a clean Mac.
- Trademark/naming search before publishing.
- Versioning and update policy (no auto-updater yet).

## Milestone 5 — iPhone (research only)

See `ios-strategy.md`. Gate: choose B (own Realtime voice) or C (manual companion). Strategy A is
not viable with public APIs. No iOS code exists yet.

## Milestone 6 — Other platforms (not started)

- **Windows:** WASAPI process loopback, GSMTC media sessions, native UI.
- **Android:** `AudioPlaybackCaptureConfiguration` (app consent required), `MediaSessionManager`.
- **Linux:** PipeWire stream monitoring, MPRIS.

Reuse the coordinator contract and the test fixtures. Do not introduce a second runtime into the
macOS app for hypothetical portability.

## Near-term backlog

1. Supervised live test with ChatGPT Voice + Apple Music; record latency and errors.
2. Verify helper-process audio: does the main ChatGPT process or a helper produce voice output?
3. Measure pause/resume latency, CPU, memory, battery over a 30-minute session.
4. Device matrix: wired, Bluetooth, AirPods, multi-output, device switch mid-answer.
5. Harden AppleScript error mapping with real denial/quit scenarios.
6. Optional: microphone-based "pause while I speak" (separate permission, explicit opt-in).
7. Optional: volume ducking where the provider supports it, restoring gain precisely.
8. Optional: a tiny local VAD to reduce false positives from notification sounds.
9. Add Spotify/VLC adapters behind capability declarations.
10. Developer ID signing, notarization, DMG, and a clean-machine install test.

## Non-goals

- Replacing ChatGPT, recording/transcribing conversations, or becoming a general automation tool.
- Cross-app audio capture on iOS or any private-API workaround.
- Cloud accounts, analytics, or a backend for the macOS core.
