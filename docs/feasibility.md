# Feasibility and capability matrix

Research date: November 2026. Environment used for experimental checks: macOS 26.6.2 (25G83),
Apple M2, Swift 6.3.3, Command Line Tools only.

Legend:

- **Supported** — public, documented API.
- **Supported + permission** — works, but the user must grant a macOS privacy permission.
- **Experimental** — works technically, but the mapping to "ChatGPT is speaking" is not reliable.
- **Unavailable** — no supported public API.
- **Unverified** — believed possible, not exercised here.

## Core capabilities

| Capability | Status | Requires | Evidence / notes |
| --- | --- | --- | --- |
| Read one app's audio output on macOS 14.2+ | Supported + permission | System audio recording TCC, `NSAudioCaptureUsageDescription` | Implemented with `CATapDescription` + `AudioHardwareCreateProcessTap` + private aggregate device. Verified with a controlled process: `say` produced `activity started at -20.8 dBFS`, then `activity ended`. |
| Discover audio-producing processes and their bundle IDs | Supported | same TCC on first tap | `AudioProcessCatalog` enumerated 32 real Core Audio process objects on the test Mac. |
| Keep target app's audio audible while tapping | Supported | — | Tap is unmuted and private; the aggregate device is only for analysis. |
| Control Music play/pause without changing track or queue | Supported + permission | Automation TCC, `NSAppleEventsUsageDescription` | `NSAppleScript` against `com.apple.Music`; scripts guard on `application "Music" is running` and never call next/previous/stop or change volume. Unit-tested generation/parsing; **live command path not executed** because the Automation consent dialog could not be approved non-interactively. |
| Detect whether ChatGPT is speaking | Experimental | OpenAI has no public desktop speech-event API | Oreja detects **audio output activity** from the selected process. That is not a speech classifier. Notifications/sound effects can trigger it. |
| Run without an OpenAI API key or account | Supported | — | No network code exists in the app. |
| Keep all processing local | Supported | — | Only dBFS levels are computed; buffers are never written or sent anywhere. |
| Start at login | Supported | User approval in System Settings | `SMAppService.mainApp`; toggle in Settings/onboarding. |
| Menu bar-only utility | Supported | — | `MenuBarExtra` + `LSUIElement`, no Dock icon. |
| Distribute via Mac App Store | Unverified, likely unsuitable | Sandbox + automation exception | Process taps are permitted for sandboxed apps with the audio-input entitlement, but controlling another app through Apple Events in a sandbox requires temporary exception entitlements and review justification. Direct distribution is the supported path here. |
| Notarize | Not done | Apple Developer ID certificate | Ad-hoc signed only. Steps are in `distribution.md`; no credentials were available. |

## ChatGPT desktop and web

| Question | Finding | Confidence |
| --- | --- | --- |
| Is there a public API that reports when ChatGPT starts/stops speaking? | No public consumer-desktop event API was found. The app is not scriptable for voice state. | High (absence of documentation), but re-check each release. |
| Can Oreja detect voice output without such an API? | Yes, on macOS, by tapping the app's audio processes. | Verified for process taps generally; not verified with a live ChatGPT voice session. |
| Which bundle identifiers exist? | `com.openai.chat`, `com.openai.chatgpt` (historical) and `com.openai.codex` (2026 desktop build). The test Mac has `/Applications/ChatGPT.app` with `com.openai.codex`. | Observed + catalog. |
| Do helper processes produce the audio? | Possibly. Oreja matches the `com.openai.` prefix and taps every matching process that is running output, falling back to all matching processes. | Design choice; needs live confirmation. |
| Does the old macOS Classic voice experience still exist? | No — retired January 2026. Voice now appears in the ChatGPT desktop Work/Codex experience and on chatgpt.com. | Based on OpenAI Help Center reporting. |
| Can browser ChatGPT be monitored? | Technically yes, but a browser tap captures **all** audio from that browser. Safari and Chrome are selectable and labelled experimental; other browser identifiers are catalogued but not shown yet. No DOM observation is used. | High for the limitation; unverified behavior. |
| Does a ChatGPT plugin/connector help? | No. Plugins cannot monitor arbitrary audio or control local apps. | High. |

## macOS APIs evaluated

| API | Use | Decision |
| --- | --- | --- |
| Core Audio process taps (`CATapDescription`, `AudioHardwareCreateProcessTap`, aggregate device, IOProc) | Detect AI output | **Chosen.** Targeted, unmuted, private, documented. macOS 14.2+. |
| ScreenCaptureKit audio | System/display audio capture | Rejected: display-scoped, heavier permissions/UI, unnecessary for one app's audio. |
| Virtual audio devices (BlackHole, Loopback) | Reroute audio to observe it | Rejected: changes the user's audio chain, may mute/reroute ChatGPT, extra install. |
| Microphone + VAD | Detect speech | Rejected for the default behavior: hears the user and speakers, requires microphone permission. Possible future opt-in. |
| Apple Events / `NSAppleScript` | Music control | **Chosen.** No private API, no extra dependency; requires Automation consent. |
| Scripting Bridge | Music control | Rejected: generated headers are brittle; AppleScript is small here. |
| MusicKit `SystemMusicPlayer` | Music control | Rejected on macOS: oriented to the app's own Apple Music playback and subscription; cannot reliably pause an already-playing Music.app session. |
| `SMAppService` | Launch at login | **Chosen.** |
| `MenuBarExtra` | UI | **Chosen.** Native, lightweight. |

### Open-source references inspected

- Apple's *Capturing system audio with Core Audio taps* documentation.
- `firedanceio/macos-audio-tap` — minimal tap + aggregate device lifecycle.
- `CJStanfield/CoreAudioTapKit` — lifecycle and permission handling patterns.
- `dws741119/SoundRouter` — aggregate device/tap routing pitfalls.
- A community write-up of a working minimal tap implementation (maven.de, 2025).

No third-party code or package was imported. The implementation follows the documented lifecycle
directly: create tap → private aggregate device containing the tap → IOProc on the aggregate →
start/stop and destroy in order. This keeps the dependency surface at zero and the audio path
auditable. The main lifecycle pitfalls (unmuted tap, private aggregate, tap list keyed by tap UID,
teardown order) are handled explicitly in `ProcessAudioMonitor`.

## Permission and distribution findings

- Process taps require the **System Audio Recording** permission; without it the tap creation
  fails. The app maps the failure to an actionable `permissionRequired` state.
- Apple Events to Music require Automation consent. The user sees a standard macOS dialog the first
  time Oreja tries to read or control Music.
- No root, kernel extension, accessibility, screen-content, or microphone access is needed.
- Ad-hoc signing plus `device.audio-input` and
  `automation.apple-events` entitlements is sufficient for local use. TCC identifies an ad-hoc app
  by its signature; **rebuilding changes the signature and may require re-granting permissions**.
- Notarization requires a Developer ID certificate and an app-specific password; not performed.

## iOS (summary)

Cross-app audio monitoring is **unavailable** through public APIs on iOS. There is no equivalent of
a Core Audio process tap, and an app cannot silently observe another app's output. ReplayKit only
captures after an explicit user broadcast, and audio sessions/interruptions do not expose another
app's speech state. Three strategies are analysed in `ios-strategy.md`; the honest choice is either
a limited companion or an Oreja-owned realtime voice client with its own API cost.

## Windows, Android, Linux (summary)

- **Windows**: WASAPI process loopback (`ActivateAudioInterfaceAsync` with process-tree inclusion,
  Windows 10 2004+) can capture one app's audio; media control via
  `GlobalSystemMediaTransportControlsSessionManager`. Feasible, not implemented.
- **Android**: `AudioPlaybackCaptureConfiguration` only captures apps that allow capture, in the
  same user profile, with user consent; media control via `MediaSessionManager` (notification
  listener permission). Partial coverage, app-dependent. Not implemented.
- **Linux**: PipeWire can expose per-application streams; MPRIS controls players on the session
  bus. Desktop-dependent. Not implemented.

## Risks

1. **No speech-event API.** The product depends on output activity, so sound effects may pause
   music. Mitigation: documented behavior, future classifier, optional minimum-duration tuning.
2. **ChatGPT changes.** Bundle identifiers have already changed once. The catalog matches known IDs
   and the `com.openai.` prefix, but a new app identity would need an update.
3. **TCC friction.** Two permissions, both user-visible; ad-hoc rebuilds can reset them.
4. **Apple Music edge cases.** Radio, lossless, AirPlay, and Music quitting mid-command need live
   testing.
5. **Trademark.** "Oreja de Van Gogh" has not been cleared. Do not publish under it before a
   trademark and brand-confusion search.
6. **App Store.** Sandboxed Apple Events automation may be rejected or require exception
   entitlements. Direct distribution is the fallback and the current path.

## What remains unverified

- A live ChatGPT Voice session producing audio, and Oreja pausing/resuming Apple Music in response.
- Real Apple Music control after Automation consent.
- End-to-end latency, CPU, memory, and battery measurements.
- Bluetooth/AirPods/multi-output/device switching during an actual conversation.
- Behavior across macOS 14.2–15.x (only 26.6.2 was available).
- Whether helper processes alone carry ChatGPT's voice audio.
- Notarization and Gatekeeper on a second Mac.
