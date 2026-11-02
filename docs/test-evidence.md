# Test evidence

Date: 2026-11-01
Machine: MacBook (Apple M2), macOS 26.6.2 (25G83), Swift 6.3.3, Command Line Tools only (no Xcode,
no XCTest runtime, broken SwiftPM manifest library).

Every result below was produced by the command shown. Items that were not executed are listed under
[Not executed](#not-executed) and are **not** counted as passes.

## Automated suite

```bash
./scripts/test.sh
```

Result (historical run recorded below; current UI release verification is listed separately):

```
51 passed, 0 failed, 261 assertions
```

Current UI release verification (2026-11-01): `./scripts/test.sh` → **54 passed, 0 failed, 283
assertions**; `python3 scripts/check-site.py` → site consistent; `git diff --check` → clean;
`./scripts/build.sh` → app valid on disk and satisfies its designated requirement.

Coverage (names as printed by the suite):

| Area | Cases |
| --- | --- |
| Coordinator | music playing + AI audio = pause; quiet + threshold = resume; stale "playing" after a successful pause still resumes; brief gap stays paused; already-paused music is not resumed; manual pause blocks resume; manual resume is honored; ChatGPT process exit; Music exit; permission revoked; device change; two rapid responses; non-speech output; sleep/wake; track changed while paused; quit while owning a pause; delayed pause + end of speech; AI resumes during an in-flight resume; command failure limit; disabling automation; commands without a valid source |
| Detector | dBFS conversion; minimum activity duration; sub-threshold blips; silence duration; hysteresis; short gaps; reset; level-sampler averaging |
| Media/settings | AppleScript state parsing (playing/paused/stopped/unavailable); scripts never launch/stop/clear the track; track identity; settings round-trip and clamping; unknown/missing fields; separate defaults keys; stale-pause recovery; ChatGPT/browser catalog matching; quiet-interval clamping; mock provider |

The suite is an executable, not XCTest, because this machine has no XCTest runtime. The test cases
are plain functions and will migrate to Swift Testing on a full Xcode toolchain.

## Build and launch

```bash
./scripts/build.sh --probe --harness
open build/Oreja.app
codesign --verify --strict build/Oreja.app
```

Observed:

```
Built: .../build/Oreja.app
... valid on disk
... satisfies its Designated Requirement
```

- `build/Oreja.app`: ~2.8 MB, executable 863,520 bytes.
- Signature: `Signature=adhoc`, `flags=0x10002(adhoc,runtime)`, identifier `app.oreja.van-gogh`,
  no TeamIdentifier (no Developer ID). `codesign --verify --strict` passed.
- Entitlements read back from the signature:
  `app-sandbox=false`, `device.audio-input=true`, `automation.apple-events=true`.
- The app launched (`open`), the process stayed alive for 10+ seconds, and it was then terminated.
  It runs as an accessory app (`LSUIElement`); no Dock icon.
- The generated icon is a valid `.icns`; the 512@2x source is 1024×1024.

Not verified: an interactive walk through all six onboarding screens. The UI code compiled and the
app launched; onboarding and the live-test UI were not clicked through by an automated agent.

## Real Core Audio process discovery

```bash
./build/bin/oreja-probe --list
```

Observed 32 real Core Audio process objects. Notable entries:

```
pid 1939  output=no   com.openai.codex.helper
pid 9439  output=no   com.openai.codex.helper
pid 1993  output=no   com.openai.sky.CUAService
pid 55877 output=no   com.tinyspeck.slackmacgap.helper
```

`/Applications/ChatGPT.app` is installed with bundle identifier `com.openai.codex` and was running
at the time. This confirms the catalog matches the 2026 ChatGPT desktop identity.

## Real process-tap capture

The first attempt to tap `afplay` by bundle prefix found nothing: `afplay` has no bundle identifier
in the Core Audio process list (it appeared as a process with no bundle ID). `oreja-probe` was
therefore extended with `--pid`, and `ProcessAudioMonitor` with an explicit-target initializer used
only by the probe.

```bash
( for i in $(seq 1 12); do say -v Samantha "Hello, this is a test of the Oreja audio monitor."; done ) &
sleep 1
./build/bin/oreja-probe --pid "$(pgrep -x say | head -1)" --seconds 6
```

Observed:

```
Oreja audio probe
Tapping pid 900 (, output=true).
Monitoring for 6s. Speak in the target app. Ctrl-C to stop.
• monitoring pid 900 (1 audio process)
▶ activity started at -20.8 dBFS
■ activity ended at -100.0 dBFS
• stopped: Monitoring stopped.
Done. No audio was stored.
probe exit: 0
```

This verifies, on real hardware and the real macOS audio stack: process discovery, private tap and
aggregate-device creation, unmuted capture, IOProc delivery, level analysis, onset detection,
silence detection, and clean teardown. It does **not** verify ChatGPT's voice path or Apple Music.

An earlier run of the probe hung waiting for events after its deadline; the probe now enforces its
own timeout and calls `stop()`. The app itself does not have that bug (its monitor lifecycle is
owned by `AppModel` and is covered by coordinator tests).

## Real Apple Music integration and measured latency

This is the full chain on real hardware: a controlled audio process → Core Audio process tap →
level detector → `PlaybackCoordinator` → `AppleMusicController` → the real Music app. It excludes
only ChatGPT itself.

### Method

A 44.1 kHz stereo WAV with 3.0 s of silence, 2.5 s of a 440 Hz tone, then 6 s of silence:

```bash
python3 - <<'PY'
import wave, struct, math
rate = 44100
def tone(seconds, freq=440, amp=0.18):
    out = bytearray()
    for i in range(int(rate * seconds)):
        s = int(amp * math.sin(2 * math.pi * freq * i / rate) * 32767)
        out += struct.pack('<hh', s, s)
    return bytes(out)
with wave.open('/tmp/oreja-test.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(b'\x00' * (rate * 3 * 4))
    w.writeframes(tone(2.5))
    w.writeframes(b'\x00' * (rate * 6 * 4))
PY
./scripts/build.sh --harness
./build/bin/oreja-integration --file /tmp/oreja-test.wav --lead 3 --tone 2.5 --seconds 11
```

The harness launches `afplay` itself, taps **only that process** (Music is excluded), and wires the
real coordinator with the default 800 ms quiet interval and detector defaults.
[`tools/IntegrationHarness`](../tools/IntegrationHarness/main.swift).

Music had Automation permission and was playing a local library track. Three consecutive runs:

| Metric | Run 1 | Run 2 | Run 3 | Run 4 (after packaging fix) |
| --- | ---: | ---: | ---: | ---: |
| Activity event after nominal tone start | 356 ms | 313 ms | 331 ms | 417 ms |
| Coordinator pause decision | 0 ms | 0 ms | 0 ms | 0 ms |
| Apple Music pause command (confirm included) | 275 ms | 258 ms | 284 ms | 270 ms |
| Observed pause path (nominal tone start → Music paused) | 631 ms | 570 ms | 616 ms | 687 ms |
| Detector silence recognition after nominal tone end | 565 ms | 530 ms | 551 ms | 618 ms |
| Quiet interval before resume | 844 ms | 846 ms | 843 ms | 844 ms |
| Apple Music resume command (confirm included) | 269 ms | 278 ms | 272 ms | 258 ms |
| Observed resume path (nominal tone end → Music playing) | 1679 ms | 1654 ms | 1666 ms | 1721 ms |
| Pause / resume commands | 1 / 1 | 1 / 1 | 1 / 1 | 1 / 1 |
| Result | PASS | PASS | PASS | PASS |

In every run Music was observed `paused` during the tone and `playing` afterwards, on the same
track, with no reset. A separate position check showed pause actually freezes playback:
`p1=1.041 s`, pause 2 s, `p2=1.046 s`, resume 1.2 s, `p3=2.194 s`.

### What the numbers include (and do not)

- The harness defines "tone start" as the fixture launch plus the file's 3 s lead. `afplay` process
  startup is therefore included in the 313–356 ms onset figure and the 570–631 ms pause path. Those
  are **upper bounds**, not pure Core Audio latency.
- The Music command figures include the new state-confirmation wait (below), so they are the time
  from command issue to Music actually reporting the new state.
- Resume path includes the detector's 250 ms silence window plus the 800 ms user quiet interval
  (measured at 843–846 ms) plus the command.
- The default output device only. No Bluetooth, AirPods, AirPlay, multi-output, or device switching.
- No ChatGPT audio. This is a fixture, not a voice session.

### Target assessment (first design)

The master prompt targets a pause within **250 ms** of reliably detected output onset. With the
first adapter design that target was **not met**: the Music command alone took 258–284 ms, because
it was a command round trip plus a separate state read. Both fixes below were then implemented and
measured; see [Latency fix](#latency-fix) for the current numbers.

### Latency fix

Two changes, both in the real adapter rather than the test harness:

1. **One Apple Event per command.** `AppleMusicScript.pauseReporting` / `resumeReporting` run the
   command and read the resulting snapshot inside the same AppleScript, waiting inside Music for the
   new state (up to 20 × 10 ms). The adapter returns that snapshot through the new
   `pauseReporting()` / `resumeReporting()` port methods, so the coordinator no longer pays a second
   round trip to learn what its own command did.
2. **Compiled scripts are cached.** `NSAppleScript` compiles its source on first execution; a new
   instance per call paid that cost on every pause and resume. `AppleScriptRunner` now keeps one
   compiled instance per source string.

Providers that do not implement the reporting methods inherit a default that pauses and then reads
the state, so no adapter is forced to change. Two tests cover this: the scripts issue the right verb
and wait for the right state, and the default implementation falls back to `pause()` plus a state
read (suite: 42 tests, 211 assertions).

### Re-measured after the fix (real Music, same fixture)

| Metric | Run 5 | Run 6 | Run 7 |
| --- | ---: | ---: | ---: |
| Activity event after nominal tone start | 429 ms | 401 ms | 363 ms |
| Apple Music pause command (one round trip, confirm included) | 201 ms | 188 ms | 187 ms |
| **Detected onset → Music actually paused** | **201 ms** | **189 ms** | **187 ms** |
| Quiet interval before resume | 844 ms | 813 ms | 846 ms |
| Apple Music resume command | 196 ms | 167 ms | 196 ms |
| Result | PASS | PASS | PASS |

**Target status: met.** The spec asks for a pause within 250 ms of reliably detected output onset;
that interval is now 187–201 ms across three runs, down from 570–687 ms in the first design. Two
honest caveats: the fixture process needs 363–429 ms from launch to a detected onset (that portion is
`afplay` startup plus the 60 ms onset debounce, and would not apply to an already-running ChatGPT),
and none of this has been measured against real ChatGPT audio.

The end-to-end figure a user would feel — sound begins to music paused — is 550–630 ms in this
fixture. Resume is unchanged in design and still about 1.65–1.72 s from the nominal end of speech,
most of which is the deliberate 250 ms detector window plus the 800 ms user quiet interval.

### Bug found and fixed by this test

The first harness run failed: the pause command succeeded, but the immediately following state read
still returned `playing`. The coordinator then treated the pause as stale, released ownership at the
end of the quiet interval, and **left Music paused forever**. Two fixes:

1. `AppleMusicController.pause()`/`resume()` now wait (up to ~500 ms) for Music to report the new
   state before returning.
2. `PlaybackCoordinator` now issues a harmless resume when it owns a pause but the provider reports
   a stale `playing` snapshot, instead of stranding playback. This is covered by the new
   "stale playing snapshot after a successful pause still resumes" test.

The fix was rerun three times; the table above is the post-fix evidence.

### Environment note

## Real ChatGPT acceptance attempts

### ChatGPT web in ego lite — executed, failed to trigger Oreja

Configuration: Oreja was configured to monitor `com.citrolabs.ego.lite` and Apple Music was
playing. In a logged-in ChatGPT web session, I created a new chat and used both:

- Read aloud on a completed response; the UI changed to “Stop reading aloud”.
- Voice mode; the UI showed an active microphone, then ChatGPT visibly answered “Four.” to a
  spoken-mode prompt.

During both cases Apple Music remained `playing` for the observation window. The Oreja log added
no activity, pause, or resume event. A concurrent probe against the matching
`com.citrolabs.ego.helper` processes found the processes but captured no activity. The process
catalog reported `output=no` for the matching helper processes. This is a real web failure, not a
coordinator failure: the live web response was visible, but its audio was not exposed through the
process tap target available to Oreja.

Normal Google Chrome was also checked. `chatgpt.com` is logged out; its guest “Meet Voice” page
shows a disabled “Tap to talk” control, so a genuine Chrome Voice test requires the user to sign in
manually. No credentials were entered and no login state was bypassed.

Per the acceptance retest, Chrome was not used for the latest browser check. With Oreja explicitly
configured for ego lite, a real logged-in ego Voice response (“Two plus three equals five.”) was
visible and the Voice UI showed an active microphone. The matching three ego processes still all
reported `output=no`; `oreja-probe --bundle com.citrolabs.ego --seconds 18` captured no samples,
Oreja emitted no activity event, and Apple Music remained `playing`. The ego Voice session was
ended cleanly afterward.

### ChatGPT desktop app — executed successfully

Oreja was reconfigured to the desktop source (`com.openai.codex`) and restarted. The app log
confirmed `Monitoring ChatGPT (4 audio processes)`. I switched the installed desktop app from
Codex mode into ChatGPT mode, opened an existing real Voice conversation, and activated its
“Read aloud” control twice. The matching desktop probe captured activity at −19.0 dBFS and
Apple Music paused on each turn:

- 15:12:44: `Paused Apple Music (Clásico — LAGOS)`.
- 15:14:30: `Paused Apple Music (Rakata — Wisin & Yandel)`.

After stopping each read-aloud playback, Apple Music resumed after the configured 12-second
conversation hold (15:14:04 and 15:14:52). This verifies the real desktop AI-output path and
repeat-turn behavior. The earlier accessibility “unsupported” result was an automation-reporting
limitation; the coordinate action was visibly confirmed by the desktop UI changing to “Stop
reading aloud”.

### Human microphone path — executed manually

The implementation was corrected so user speech can initiate a pause when the person speaks first,
and the coordinator regression case
`19b. user speech can start a pause when the person speaks first` passes. I enabled
`pauseWhileISpeak`, temporarily routed the default input/output to the built-in microphone and
speakers, and ran a local `say` voice signal after restarting Oreja with those devices selected.
AVAudioEngine captured the acoustic signal and Oreja logged `Your voice is active; pausing music`
at 15:20:24, then paused Apple Music at 15:20:25. The Sony Bluetooth input/output defaults were
restored and Oreja was relaunched; Music returned to `playing`. This verifies the microphone signal
path. In a later manual speech window with the Sony microphone selected, Oreja logged user voice
activity at 15:21:50, 15:21:55, 15:22:01, 15:22:04, and 15:22:09; Music stayed paused throughout
and resumed at 15:22:23 after the final quiet interval. This is the real person-speaking acceptance
case. A Bluetooth-noise false-positive was then found: the Sony mic produced idle spikes in the
high −30s dBFS and could re-pause Music. The microphone detector threshold was raised to −25 dBFS
(deactivation −35 dBFS). The rebuilt app stayed `playing` for 20 seconds of Sony-mic idle with no
voice or playback events. A final built-in-mic speech proxy at output volume 100 still logged user
voice activity and paused Music; volume was restored to 67 and Sony input/output were restored.

### Current acceptance conclusion

The controlled fixture, real `say` probe, and real ChatGPT desktop read-aloud test verify Core
Audio capture, detection, coordinator pause/resume, and Apple Music control. The real ChatGPT web
Voice case still does not work in the tested ego browser session because it exposes no capturable
output. The microphone signal path and a manual person-speaking pause are verified. The 5% volume
option is not
implemented; Apple Music only advertises pause/resume capability (`canSetVolume = false`).

One library item reported `player state = playing` but exposed no `current track`
(`-1728`/`-1700`). Oreja still observes the state and can pause/resume; only track identity is
missing. The harness requires a track with metadata and used a different library item. This edge
should be kept in mind for ownership when a provider hides track identity.

## Packaging bug found by this check

After the last source change the rebuilt app **did not launch at all**. Running the binary directly
showed:

```
dyld: Library not loaded: @rpath/libOrejaCore.dylib
  Reason: … 'libOrejaCore.dylib' not valid for use in process: mapping process and mapped file
  (non-platform) have different Team IDs
```

Two packaging defects, both real:

1. The dylibs were linked with **absolute** install names (`/…/build/lib/libOrejaCore.dylib`). The
   app therefore loaded the linker-signed build artifacts instead of its bundled copies, so
   `build/Oreja.app` was not relocatable and could not run without `build/lib`.
2. The app was signed with `--options runtime` (**hardened runtime**) and ad-hoc identity. Hardened
   runtime enables library validation, and an ad-hoc signature has no team identity, so validation
   rejects even Oreja's own dylibs. The app aborted in dyld.

Fixed in `scripts/build.sh`: dylibs get `-install_name @rpath/lib…dylib`, and the hardened runtime
is applied only when a real identity is provided (`OREJA_SIGN_IDENTITY="Developer ID …"`). After the
fix the app loads its own `Contents/Frameworks` libraries, idles at 0.0–0.1% CPU (~37–54 MB
physical footprint, sampled over 48 s), and still launches when `build/lib` is moved away.

Consequence for the record: the earlier "the app launches and stays resident" claim in
`docs/test-results.md` was based on `pgrep` alone and was a **false positive** — the process existed
but was stuck in dyld. That claim has been corrected there.

## Idle resource use

Menu bar app idle, automation disabled, no tap running, sampled every 8 s for 48 s:

| Metric | Value |
| --- | --- |
| CPU | 0.0–0.1% (`ps -o %cpu`) |
| Physical footprint | 36.7–54.4 MB, fluctuating with SwiftUI/AppKit lazy loads |
| Resident set | 112 KB reported by `ps -o rss` (under-reports; use `vmmap`) |

Not measured: CPU/memory/battery during an active tap, and during a real conversation.

## Real ChatGPT: web attempted, desktop partially attempted

A second attempt was made to run the real acceptance test on this machine. What was found:

- `/Applications/ChatGPT.app` (version 26.1021.31345, bundle `com.openai.codex`) is installed and
  running as pid 1227 with its Codex helper processes.
- The app has **no window** by default. `activate` briefly produces one transient window titled
  `Research Voice Plugin App`, which closes again, and `entire contents of window 1` returns an empty
  accessibility tree, so there is no scriptable composer, response, or read-aloud control.
- Its menu bar (`ChatGPT`, `File`, `Edit`, `View`, `Window`, `Help`) contains no Voice command.
- Accessibility permission itself is granted (`UI elements enabled` is `true`), so the limitation is
  the app's tree, not the automation permission.
- No Chromium remote-debugging port is listening on any ChatGPT helper, so the renderer cannot be
  driven directly.
- A logged-in ego lite web session was available and was used for the real web attempt. The
  response/read-aloud and Voice UI visibly produced responses, but the matching helper processes
  exposed no capturable output and Apple Music stayed playing; see [Real ChatGPT acceptance
  attempts](#real-chatgpt-acceptance-attempts).
- Chrome was open but logged out, so it was not used for a ChatGPT account test.

The desktop app's “Read aloud” control could not be invoked through the available accessibility
action (the action was reported unsupported/unverified). No desktop audio result is claimed. A
human microphone path was also not executed.

The exact supervised procedure that would close this gap is in
[compatibility.md](compatibility.md) and the release checklist in [distribution.md](distribution.md).

## Not executed

| Test | Why | Status |
| --- | --- | --- |
| Real ChatGPT Voice → Oreja → Apple Music pause/resume | Web Voice was executed but no capturable helper output appeared; desktop control was unsupported/unverified | **Failed / desktop not verified** |
| CPU, memory, battery impact during a real conversation | Requires a real session | **Not measured** |
| Bluetooth / AirPods / wired / multi-output / device switching | No such devices were exercised | **Not tested** |
| macOS 14.2–15.x compatibility | Only macOS 26.6.2 available | **Not tested** |
| Gatekeeper/notarization on a second Mac | No Developer ID credentials | **Not performed** |
| Onboarding click-through | Interactive UI test not run | **Not tested** |

## Design timing budget (not measurements)

| Stage | Value | Source |
| --- | --- | --- |
| Onset debounce | 60 ms | `PlaybackPolicy.minimumActivityDuration` |
| Analysis tick | ≤ 50 ms | `ProcessAudioMonitor.analysisInterval` |
| Detector silence window | 250 ms | default policy |
| Resume delay | 300–3000 ms, default 800 ms | user setting |
| AppleScript command (one round trip, in-script confirm) | 187–201 ms | measured, `Latency fix` |

Pause begins roughly 110 ms plus about 190 ms of command work after sustained audio onset, which is
why detected onset → paused measured 187–201 ms and the 250 ms target is met. The figure that
includes the fixture player starting up stays 550–630 ms and should not be quoted as Oreja's
latency; against an already-running ChatGPT only detection plus the command apply.

## Manual acceptance procedure

1. Sign in to the ChatGPT desktop app and start a Voice conversation.
2. Start Apple Music playing an album.
3. Launch `build/Oreja.app`, complete onboarding, grant both permissions, and enable automation.
4. Ask ChatGPT a question.
5. Confirm: panel shows "ChatGPT is speaking"; Music pauses; panel shows "Waiting for silence";
   Music resumes the same song at the same position.
6. Pause Music yourself while ChatGPT is speaking; confirm Oreja does not resume it.
7. Quit ChatGPT mid-answer; confirm music returns and no error loop occurs.
8. Record latency (screen recording or log timestamps) and repeat across output devices.

Until that run is completed, the macOS MVP's core integration is verified by component and
capture tests only, not by a live conversation.

## UI and brand verification (2026-11-01)

Executed after the presentation layer was rebuilt on `apps/macos/Theme.swift` and the brand assets
were added:

- `./scripts/build.sh` → exit 0. `build/Oreja.app` is ad-hoc signed, and `codesign --verify` passes.
- `./scripts/test.sh` → 44 passed, 0 failed, 228 assertions.
- `swiftc -typecheck -I build/modules apps/macos/*.swift` → 0 diagnostics.
- `open build/Oreja.app` → resident process; `vmmap -summary` physical footprint 26.0 MB (peak
  28.8 MB); `lsof` shows `Contents/Frameworks/libOrejaCore.dylib`, `libOrejaAudio.dylib` and
  `libOrejaMedia.dylib` loaded.
- `site/index.html` and `site/docs.html` parse with balanced tags, every in-page anchor and relative
  link resolves, `site/styles.css` braces balance, and no `http(s)` URL appears anywhere in `site/`.
- `site/assets/mark.svg` and the generated `AppIcon.iconset/icon_512x512.png` were rendered locally
  and inspected at 512 px.

Not verified and therefore not claimed: the live menu bar panel and windows in light and dark
appearance (no screenshot was taken), the site in a browser, live ChatGPT Voice, and notarization.

## Conversation-mode pass (2026-11-01, second session)

Trigger: the user reported that in a real spoken conversation — Music playing, Oreja running, then
ChatGPT (app or web) in conversation mode — music did not reliably stop while the AI or the user was
talking, and did not reliably come back while the agent was working.

### Root causes found

1. **The tap targeted a snapshot of processes taken at start-up.** Voice sessions appear *after*
   monitoring begins: Chromium creates its audio utility process on first playback, and ChatGPT
   spawns renderer/helper processes when a conversation starts. Those processes were never tapped,
   so a correct setup could detect nothing at all until Oreja was restarted mid-session.
2. **A dead monitor never recovered.** When the monitored app quit or dropped its audio processes,
   the failure was reported but nothing retried, so Oreja stayed "monitoring" nothing.
3. **Re-targeting churned at speech onset.** The monitor preferred processes that reported
   `isRunningOutput`; apps toggle that flag per turn, so the tap was rebuilt exactly when a sentence
   started and the first syllables were lost.
4. **Environment, not code:** every rebuild changes the ad-hoc signature, so macOS re-asks for System
   Audio Recording and the tap call blocks until the dialog is answered. Unanswered, Oreja looks
   completely dead. This is now documented in `troubleshooting.md`.

### Fixes

- The monitor re-evaluates the target set: event-driven on `kAudioHardwarePropertyProcessObjectList`
  changes, with a 1 s poll as a fallback, and rebuilds the tap when the set changes.
- It taps **all** matching processes (quiet ones included) instead of only those reporting output, so
  a process that starts speaking is already tapped.
- The aggregate device is asked for a 1024-frame IO buffer; the analysis tick dropped from 50 ms to
  30 ms.
- `AppModel` retries monitoring every 3 s after a non-permission failure.
- "No audio process yet" is now `searchingForSource`, not an error.
- Diagnostics are mirrored to `~/Library/Logs/Oreja/oreja.log`.

### Measurements (real Core Audio tap, real Music)

Controlled source: `tools/AudioFixture` (its own bundle id, `com.oreja.fixture`), which reports the
exact host time at which it starts rendering its first non-silent sample. Music: Apple Music playing
a real track, `song repeat = one`.

| Measurement | Command | Result |
| --- | --- | --- |
| Fixture audible → activity started (probe) | `build/bin/oreja-probe --bundle com.oreja.fixture` | 136 ms |
| Fixture audible → Music actually paused (app chain, 50 ms polling) | `open build/Oreja.app` + fixture | **+0.33 s** |
| Last syllable → Music playing again (default 800 ms quiet interval) | same | +1.4–1.7 s |
| Two "sentences" with a 0.4 s gap | two fixture instances 0.53 s apart | one pause, one resume — no oscillation |
| Audio process appears *after* monitoring started | silent fixture + second speaking fixture | detected, paused, resumed |
| Browser source (Chrome web audio, two sentences, 0.4 s gap) | `open -a "Google Chrome" /tmp/oreja-two.html` | one pause ~0.44 s after the first syllable, one resume 1.42 s after the second |

The 0.33–0.44 s figures include Music's own AppleScript round trip (187–201 ms measured separately)
and, for Chrome, the browser's AudioContext start-up.

### Live ChatGPT result

The controlled source and browser fixture prove the detection/playback chain, but the real ChatGPT
web Voice output did not appear in the matching Core Audio process tap on this machine. The desktop
app and microphone-turn case remain unverified.

## ego lite (browser) source: conversation hold (2026-11-01, third session)

The complaint that started this pass: with `ego lite` as the source, music returned in the middle of
a spoken conversation — while the assistant was working on its answer — and the app had never
monitored ego at all.

### What was wrong

1. **ego lite was never tapped.** Its audio is rendered by `com.citrolabs.ego.helper`, not
   `com.citrolabs.ego.lite`, and the installed build predated the audio-process prefix mapping, so
   selecting it produced a monitor that could never see a process.
2. **Music returned between turns.** The coordinator waited only `quietInterval` (800 ms) after the
   assistant stopped, which is exactly when the assistant is silently working and the user answers.

### Verification of the tap for ego lite

```
$ build/bin/oreja-probe --bundle com.citrolabs.ego.helper --seconds 16
setup: ego lite window with a page that plays a 440 Hz tone on each keystroke (1.6 s each)
t=… ▶ activity started at -13.5 dBFS      # first tone
t=… ■ activity ended at -100.0 dBFS       # 1.8 s later
t=… ▶ activity started at -13.5 dBFS      # second tone
t=… ■ activity ended at -100.0 dBFS
t=… ▶ activity started at -13.5 dBFS      # third tone
t=… ■ activity ended at -100.0 dBFS
```

Three tones were detected with correct onsets and ends; levels are healthy (-13.5 dBFS). The probe
tapped two ego helper processes (`pid 5302`, `pid 5303`), and the app logged
`Monitoring ego lite (3 audio processes)`.

### Conversation through the app, real Music

Source `ego lite`, Music playing a real track, conversation hold at the default 12 s. Three "turns"
(1.6 s tones) with 6 s and 5 s silent gaps between them, then silence. Music state polled every
200 ms through AppleScript.

| Event | Poll trace | Oreja log (UTC) |
| --- | --- | --- |
| Turn 1 speaks | t = 2.21 s | — |
| Music paused | t = 3.54 s | pause issued 14:24:37, done 14:24:38 |
| Turn 1 ends → 12 s timer armed | — | `waiting 12000 ms` 14:24:39 |
| Turn 2 speaks (6 s gap) — still paused | t = 10.82 s | timer re-armed 14:24:47 |
| Turn 3 speaks (5 s gap) — still paused | t = 17.85 s | timer re-armed 14:24:54 |
| Music resumed | t = 32.65 s | resume issued 14:25:06, done 14:25:07 |

Exactly **one** pause and **one** resume for the whole exchange. The resume came 12.0 s after the
last turn ended (14:24:54 → 14:25:06), one hold period rather than one reply period.

### Microphone option

`pauseWhileISpeak` was switched on for one run. It started (`Listening for your voice as well.`,
tap on the selected input) but no activity was ever reported, because this machine's default output
is a pair of Sony Bluetooth headphones: the assistant's voice and the synthesized test sentence both
play *into the headphones*, which the headphone microphone cannot hear, and nothing in the room was
loud enough to cross the -40 dB activation threshold. **The microphone path is therefore still
unverified by measurement**; the code path is exercised only by inspection.

The occurring feedback risk was also fixed in this pass: the microphone may only extend a pause
while music is *not* playing, so speaker output can never make Oreja pause itself in a loop.

### Not executed

A real ego lite voice conversation (needs a person speaking into the microphone). The chain below
ChatGPT — process discovery, tap, level detection, pause, conversation hold, resume — is verified
with the browser as the source; that ego's own voice turns produce the same process activity is
inferred from the tone tests above, not observed.

### Final build, controlled source: waiting monitor + conversation hold

After the fixes above, the shipped build was re-run against `tools/AudioFixture` (source
`com.oreja.fixture`) to prove the parts that changed: the monitor now starts with **no tap** when the
app has no audio process yet, attaches itself when one appears, and holds the pause for the
configured conversation idle time.

```
14:50:43 Starting audio monitor for Oreja fixture.
14:50:44 Monitoring Oreja fixture (waiting for its audio process).     # no tap, monitor alive
14:50:50 Now listening to Oreja fixture (1 audio process).             # process appeared → tapped
14:51:47 Now listening to Oreja fixture (1 audio process).             # cold start of the run below
14:51:52 Issuing pause / Paused Apple Music                           # turn 1
14:51:54 AI is quiet; waiting 12000 ms before resuming music           # turn 1 ends
14:51:57 AI is quiet; waiting 12000 ms before resuming music           # turn 2 ends
14:52:03 AI is quiet; waiting 12000 ms before resuming music           # turn 3 ends
14:52:15 Issuing resume / Resumed Apple Music                         # 12.0 s after turn 3
```

Three turns at t = 4.7 s, 7.1 s and 14.2 s (1.6 s each, silent gaps of 0.8 s and 5.5 s): **one**
pause, **one** resume 12.0 s after the last turn ended. The earlier run of the same script also
exercised the tap teardown path — processes disappearing (4 → 3) kept monitoring alive rather than
ending it.

Known cost: when every turn is a *new* audio process (as this fixture makes it), the tap is rebuilt
and detection lands ~0.5 s after onset instead of ~0.14 s. A real app keeps one audio process across
turns, which is the path measured at 136 ms earlier in this file.

### Volume ducking implementation verification

The coordinator now supports a second interruption mode: it keeps Music playing, sets its volume to
the configured duck level (5% by default), and restores the exact volume observed before the
conversation. Existing settings without the new field migrate to this mode; the conversation hold
default is now 3 s and remains adjustable in Settings.

Automated evidence: `./scripts/test.sh` completed with **52 passed, 0 failed, 272 assertions**,
including a coordinator test that starts at 67%, ducks to 5% while playback remains `playing`, and
restores to 67%. `./scripts/build.sh --no-sign` completed successfully. The launched app was
verified with a 21.8 MB physical footprint and all three bundled Oreja dylibs loaded.

Not yet observed in this pass: a fresh live ChatGPT desktop voice turn with Apple Music visibly
playing at 5%. The implementation and deterministic test pass, but this real-device acceptance
step still needs one manual voice exchange after selecting the new setting.
