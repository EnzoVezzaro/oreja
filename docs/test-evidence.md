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

Result (final run after all source changes):

```
42 passed, 0 failed, 211 assertions
```

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

## Real ChatGPT: attempted, still not executed

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
- No Chrome or Safari session with ChatGPT was open during the test.

Producing genuine ChatGPT speech therefore needs a human: sign in, open a conversation, and either
start Voice or press read-aloud. A Voice session additionally needs a human speaking into the
microphone, because ChatGPT has nothing to respond to otherwise. Driving the user's ChatGPT account
or browser profile unattended was judged out of scope for this test, so it was not done, and no
part of the ChatGPT audio path is claimed as verified.

The exact supervised procedure that would close this gap is in
[compatibility.md](compatibility.md) and the release checklist in [distribution.md](distribution.md).

## Not executed

| Test | Why | Status |
| --- | --- | --- |
| Real ChatGPT Voice → Oreja → Apple Music pause/resume | Needs a human signed-in session that speaks into the microphone; the app exposes no scriptable window or Voice command (evidence above) | **Not executed** |
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
