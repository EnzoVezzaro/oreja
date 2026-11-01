# Test results

> This log captures an earlier build's checks. The current, consolidated evidence — including a
> real Core Audio process-tap capture — is in [`test-evidence.md`](test-evidence.md). Where the two
> disagree, `test-evidence.md` is authoritative.

Environment: macOS 26.6.2 (build 25G83), Apple Swift 6.3.3, Command Line Tools only (no Xcode, no
XCTest runtime, SwiftPM's `PackageDescription` does not link on this machine). All commands were run
from the repository root on 2026-11-01.

An entry is only listed as **passed** if the command was executed and its output observed. Everything
else is listed under *not executed*, with the reason.

## Passed

### 1. Unit and state-machine suite

```
$ ./scripts/test.sh
...
39 passed, 0 failed, 193 assertions
```

Coverage (all green):

- Coordinator scenarios 1–19: pause on AI audio; resume after the quiet interval; brief silences do
  not resume; music already paused is not resumed; manual pause after automation; manual resume
  during speech; source exit; Music exit; permission revoked; device/stream failure and retry; two
  rapid responses without oscillation; non-speech output follows the documented activity policy;
  sleep/wake reconciliation; track change while paused; quitting while owning a pause; delayed pause
  plus end of speech; AI speaking again during a resume; failure limit stops automation; disabling
  automation restores the pause; no commands without a valid source.
- Activity detection: dBFS conversion and clamping, activation duration, sub-threshold blips, silence
  duration, hysteresis, short gaps, reset, `LevelSampler` averaging.
- Apple Music: script output parsing (playing/paused/stopped/unavailable), scripts never call `stop`
  or `activate`, volume clamping, track identity checks, error mapping.
- Settings: round-trip, decode tolerance, clamping, UserDefaults separation of settings and journal.
- Recovery: stale pause only resumes the same paused track.

These tests use a scripted media controller and a manual scheduler: they prove the decision logic,
**not** that Core Audio capture or Music automation works on real audio.

### 2. Release build and signature

```
$ ./scripts/build.sh
==> OrejaCore … ==> OrejaMedia … ==> Oreja (menu bar app) … ==> Icon … ==> Bundle
==> Ad-hoc signing (no hardened runtime: ad-hoc has no team identity)
    build/Oreja.app: valid on disk
    build/Oreja.app: satisfies its Designated Requirement

Built: /Users/mac/Desktop/Github/oreja/build/Oreja.app
```

Bundle: ~2.9 MB, `Contents/{MacOS/Oreja, Info.plist, Resources/AppIcon.icns, Frameworks/*.dylib}`,
`LSUIElement` true, ad-hoc signed with the audio/automation entitlements. Dylibs use `@rpath` install
names, so the bundle runs without `build/lib`.

### 3. The app launches and stays resident

```
$ open build/Oreja.app
$ pid=$(pgrep -x Oreja); vmmap -summary $pid | grep 'Physical footprint'
Physical footprint:         45.5M
$ lsof -p $pid | grep 'oreja/.*dylib'
…/build/Oreja.app/Contents/Frameworks/libOrejaAudio.dylib
…/build/Oreja.app/Contents/Frameworks/libOrejaCore.dylib
…/build/Oreja.app/Contents/Frameworks/libOrejaMedia.dylib
$ ps -o %cpu=,rss= -p $pid     # sampled every 8 s for 48 s while idle
  0.1% / 0.0% / 0.1% / 0.0% / 0.0% / 0.0%
```

> Correction: an earlier entry in this file reported that the app "stayed alive and presented its
> onboarding window" based on `pgrep` alone. That was a **false positive**. The process was stuck in
> dyld because the dylibs were linker-signed and the app had the hardened runtime, so library
> validation rejected them; `pgrep` saw a process that had never finished loading, and it later
> aborted with `Library not loaded … different Team IDs`. The app now genuinely loads: ~45 MB
> physical footprint, SwiftUI/AppKit images mapped, its own `Contents/Frameworks` dylibs mapped,
> and 0.0–0.1% idle CPU. `open` + `pgrep` alone is not sufficient evidence for a SwiftUI app —
> check the footprint or `lsof`.

### 4. API availability in the active SDK

`AudioHardwareCreateProcessTap` and `CATapDescription.h` are present in
`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreAudio.framework`;
`Music.app` is installed. The modules that use them compile and link against that SDK.

## Not executed

| Check | Why it was not run |
| --- | --- |
| Live pause/resume with real ChatGPT voice + Apple Music | Requires an interactive ChatGPT voice session plus granting the audio-capture and Automation prompts. Not performed in this headless build session, so no latency or false-pause numbers exist yet. |
| Core Audio tap against real ChatGPT audio | Requires an interactive voice session; not performed. A controlled `say` process **was** tapped successfully — see `test-evidence.md`. |
| Audio capture with a live process (`build/bin/oreja-probe`) | **Now exercised** in `test-evidence.md`: `▶ activity started at -20.8 dBFS`, then `activity ended`. This row is kept for history; the current result is a pass. |
| Launch at login registration | `SMAppService` requires user approval and a signed app in a stable location; registering during automation would change the user's login items. |
| Audio device matrix (built-in, wired, Bluetooth, AirPods, switching) | Needs physical devices and a live session. See `docs/compatibility.md`. |
| Pause/resume latency **against real ChatGPT audio** | Measured against a controlled fixture instead: detected onset → Music paused is 187–201 ms, resume 1654–1721 ms (`test-evidence.md`). ChatGPT's own audio remains unmeasured. |
| CPU/memory during an active tap and a live conversation | Idle menu bar use was sampled (0.0–0.1% CPU, 37–54 MB); active-tap and conversation figures are not measured. |
| Notarization and Developer ID signing | No distribution credentials are available. The build is ad-hoc signed only. |
| iOS companion | Not started; see `docs/ios-strategy.md`. |

## How to run the missing integration test

```bash
./scripts/build.sh --probe
open build/Oreja.app                       # grant audio + automation permissions in onboarding
build/bin/oreja-probe --bundle com.openai. --seconds 20   # prints dBFS while ChatGPT speaks
```

Then start a song in Music, ask ChatGPT a voice question, and record in this file: detection latency,
pause latency, resume latency, false pauses, unexpected resumes. Until that is done, the end-to-end
product claim remains **unverified**.

Why this still has not run: the installed ChatGPT build (26.1021.31345, `com.openai.codex`) has no
window, no scriptable accessibility tree, no Voice menu command, and no remote-debugging port, and a
Voice session needs a human speaking into the microphone. Driving the user's account unattended was
out of scope. Evidence: `test-evidence.md` → "Real ChatGPT: attempted, still not executed".
