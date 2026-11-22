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

Current working-tree verification (2026-11-02): `./scripts/test.sh` → **69 passed, 0 failed, 334
assertions**. This run includes the new hook, sensitivity, and speech-shape unit cases. It does not
verify execution of a real macOS Shortcut, native Settings interaction, or audio detection against
a live process; those remain separate checks. The hook process runner now has a 30-second timeout,
discards child output to avoid undrained-pipe stalls, and terminates a child that does not stop
within two additional seconds. `./scripts/build.sh` also completed successfully and codesign
reported the app valid on disk and satisfying its designated requirement. The app was not launched
for an interactive UI check in this verification pass.

### Mascot and deploy verification (2026-11-01, executed)

| Check | Command | Result |
| --- | --- | --- |
| Sprite in the bundle matches the site asset | `shasum -a 256 site/assets/oreja-vincent.png build/Oreja.app/Contents/Resources/oreja-vincent.png` | identical (`e5689934…`, `0140ab3d…` after the ear change) |
| App launches and loads its frameworks | `open build/Oreja.app`, `vmmap -summary $(pgrep -x Oreja)`, `lsof -p` | footprint 19–30 MB, 3 `Contents/Frameworks` dylibs |
| Click easter egg renders | `screencapture -l <panel window id>` 160 ms after a click at the mascot | captures show the fifth frame (bandage off, eyes shut, mouth open) |
| Production serves every referenced file | `curl -I https://oreja-tau.vercel.app/{landing.js,assets/oreja-vincent.png,assets/fonts/manrope-variable.ttf,downloads/Oreja-0.1.0.dmg}` | 200 for all four; sprite and DMG byte-identical to the repository files |
| Website character does not bob | two screenshots 900 ms apart, `getComputedStyle(.vincent).transform` | `none`; frames identical |
| Website character never scrolls | `getComputedStyle` on the pinned act's sprite at p = 0.14 / 0.50 / 0.90 | `animation-name: none`, `transform: none`, `background-position: 0% 0px` and the same viewport top (272.84 px) at all three |
| Pinned conversation act holds and advances | screenshots at p = 0.14 / 0.50 / 0.90, 1440×900 and 390×844 | stage stays sticky, one panel at full strength each time, chip and AI/Music readouts follow the scroll (`--sc-p` 0.1400 / 0.5002 / 0.9001) |
| Behaviors rail actually travels | `rail.scrollWidth - innerWidth` | 568 px of overflow at 1440 wide; 0 horizontal page overflow at 390 wide |
| Page reads with reduced motion | Chrome `Emulation.setEmulatedMedia` prefers-reduced-motion: reduce | pinned act and rail still resolve their states; no transition, no magnet |
| Site structure after the rewrite | `python3 scripts/check-site.py` | 2 pages, 11 ids each, every internal link and anchor resolves |
| Four-width layout audit | Chrome via CDP at 375×812, 768×1024, 1024×768, 1440×900 | 0 horizontal page overflow, 0 clipped text nodes, pinned stage content fits its viewport at every width |
| Rail travels on desktop, swipes on phones | `scrollWidth` of the track and the stage, measured per width | 1127/915/459/568 px of overflow at 375/768/1024/1440; below 900px the act is `height: auto` with the stage `static` and `transform: none` |
| Design tokens match the stylesheet | computed styles read from the live page at 1440×900 | recorded in `docs/design-tokens.md` (`--ink` `#24211d`, 78px display, 30px frame radius, 22px pill-free card radius) |
| Downloaded DMG carries the current binary | mount, `shasum` against `build/Oreja.app`, `plutil CFBundleVersion` | identical binary, `CFBundleVersion` 2, `oreja-vincent.png` present |

Still not executed: a real ChatGPT Voice session, real Apple Music control on a clean account, and
notarization. Nothing above claims them.

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
| Speech-shape filter confirmation | 450 ms worst case, +50–135 ms measured on speech | measured, below |

Pause begins roughly 110 ms plus about 190 ms of command work after sustained audio onset, which is
why detected onset → paused measured 187–201 ms and the 250 ms target is met. The figure that
includes the fixture player starting up stays 550–630 ms and should not be quoted as Oreja's
latency; against an already-running ChatGPT only detection plus the command apply.

## Speech-shape filter against real audio (2026-11-01)

Executed with the real Core Audio process tap, a steady 440 Hz tone and an offline `say` clip played
by `afplay`, each tapped by PID. `--speech-gate` runs the app's own gate; without it the probe uses
the raw level path.

```
$ afplay /tmp/oreja-tone.wav & ./build/bin/oreja-probe --pid $! --seconds 4 --speech-gate
• monitoring pid 59869 (1 audio process)
· suppressed (a steady alert tone, not speech) at -15.0 dBFS

$ afplay /tmp/oreja-speech.aiff & ./build/bin/oreja-probe --pid $! --seconds 5 --speech-gate
• monitoring pid 61376 (1 audio process)
· suppressed (too short to be speech) at -65.8 dBFS
▶ activity started at -17.7 dBFS
■ activity ended at -93.6 dBFS
▶ activity started at -17.0 dBFS
```

- A constant tone — the shape of an alert, a chime tail or a notification loop — never starts
  activity. It is reported once as suppressed.
- A spoken sentence starts activity at full speech level and ends when the sentence ends; the
  -65.8 dBFS blip before the first word was a sub-onset blip that the gate also rejected.
- Added latency, four alternating runs on the same clip, measured from the monitor's start line to
  the first activity start: raw 0.559 s / 0.583 s, gate 0.694 s / 0.633 s, i.e. **+50–135 ms**. The
  450 ms confirmation window is the worst case, and it did not apply here because speech is
  modulated from the first syllable.

Limit of this evidence: a `say` clip played by `afplay` is not a live ChatGPT Voice session, so the
shape of a real reply (jitter, background noise in the tap, notification sounds the desktop app
plays) is still unmeasured.

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

## Multi-select audio sources (2026-11-09)

Executed:

- `./scripts/test.sh` → **83 passed, 0 failed, 372 assertions**. New cases cover: music players and
  Oreja excluded as sources; normalisation and de-duplication; one tap with merged prefixes; empty
  selection listens to nothing; coding-agent and terminal categorisation; ChatGPT helper resolution;
  unique catalog identifiers; migration from the single `aiSource` key; the multi-source key;
  music players dropped from stored settings; an explicit empty list kept; settings written without
  losing other fields.
- `./scripts/build.sh --probe --no-sign` → app and probe built. `apps/macos` is compiled by this
  script, not by `test.sh`, so the UI code is verified only by this build.
- `build/Oreja.app` launched. `vmmap` footprint 13.8 MB and three `Oreja.app/Contents/Frameworks`
  dylibs loaded. The log shows monitoring of ChatGPT after the settings migration.
- The real picker list was produced on this Mac by a temporary program against the built libraries.
  It listed ChatGPT, VS Code, Antigravity, Terminal, Slack, ego lite and other running apps, with
  running and output state. Orca (`com.stablyai.orca`) was added to the coding-agent group after
  that run; the code path is the same.

Not executed:

- Live capture with two or more selected apps at once. Only ChatGPT was run live in this session.
- Live capture of Claude desktop, Cursor, Windsurf, Zed, Warp, Ghostty, iTerm2, Chrome, Edge, Arc,
  Brave, Firefox, Siri, Zoom, Discord, Teams, or any call app with speech. Claude desktop is not
  installed on the test Mac, and the identifiers for the other apps were not confirmed against an
  installed copy.
- Whether a terminal's own audio process carries speech from `say` or a voice script. On this Mac,
  `say` runs as its own process with no bundle identifier and is not captured by selecting Terminal.
  Capturing harness speech needs process ancestry or a global tap, which is not implemented.
- Whether Safari's `com.apple.WebKit` prefix over-matches other WebKit apps in a live session.
  Not changed yet, because narrowing it needs a live Safari capture.

## End-to-end capture tests (2026-11-09)

Executed on the development Mac, with no recording and no audio stored:

1. **Real speech, pid target, gate off:** `say` (a multi-sentence reply) tapped with
   `oreja-probe --pid`. Three activity bursts were reported (−14.8, −29.8, −13.6 dBFS), with
   silence between sentences.
2. **Real speech, pid target, speech-shape gate on (`--speech-gate`):** same sentence. Three
   activity bursts passed (−26.0, −18.2, −15.5 dBFS). Speech is not suppressed by the filter.
3. **Steady alert tone, bundle target, gate on:** `OrejaFixture` (`com.oreja.fixture`, launched
   through LaunchServices with `open`) played a 4 s tone. The probe reported
   `suppressed (a steady alert tone, not speech)` at −15.1 dBFS and no activity.
4. **Full app, bundle selected through Settings:** the app's settings were pointed at the fixture
   (`aiSources` = fixture, saved under the v1 key; the previous settings were exported first and
   restored afterwards). The app log showed, in order: monitor started, waiting for audio, listening
   to the process, the steady tone ignored, and the process retargeted when the fixture exited. No
   Music command was issued, because Apple Music was not playing.

Not executed:

- Pause and resume of Apple Music during an AI reply. Apple Music was open with no track loaded,
  and AGENTS.md forbids changing playback without an explicit request. The harness
  (`oreja-integration`) requires a playing track.
- A full app run with **speech** (not a tone) from a selected app. The app-level speech path shares
  the tap and detector with the probe runs above, but was not run end to end through the coordinator.
- Real ChatGPT Voice or any other selected voice app under the app.

Observation: in run 1 two sentences separated by about 0.75 s of silence were reported as separate
bursts. The coordinator's resume delay and conversation hold exist for this case, so the music is not
resumed between sentences. This was not measured through the coordinator.

## Live test and release 0.3.0 (2026-11-10)

Live session with Apple Music playing, ChatGPT desktop open, and ego lite selected as a browser
source. The user spoke and asked ChatGPT by voice in both the desktop app and the browser.
Oreja log, 13:26–13:31 UTC:

- Settings changed to ChatGPT + ego lite at 13:27:37; both monitored.
- 7 lower-to-11 % and 7 restore-to-100 % events, one pair per reply, with the 1 s quiet interval
  between them.
- 4 microphone onsets ("Your voice is active"), 4 steady alert tones ignored, 0 errors.

Limits of this evidence: the log does not record which selected app caused each lower or restore,
so this run confirms that the browser source was active, not which app spoke each reply on its own.
A sleep/wake cycle was not run after the fix, so the sleep repair is covered by the code change and
the 83-test suite, not by a live sleep.

Release 0.3.0 checks:

- `./scripts/test.sh` → 83 passed, 0 failed, 372 assertions.
- `./scripts/build.sh` → ad-hoc signed; `codesign --verify --strict` passes; entitlements are
  app-sandbox off, audio-input on, Apple Events on.
- `open build/Oreja.app` → running, 12.2 MB physical footprint, three Oreja frameworks loaded.
- `build/Oreja-0.3.0.dmg` created with `hdiutil create`; `hdiutil verify` reports a valid checksum.
- Not notarized (no Developer ID credentials on this Mac).

## Primary and secondary audio apps (2026-11-14)

Feature branch `codex/dual-audio-sources` adds separate primary (`aiSources`) and secondary
(`targetAudioApps`) app selections. The coordinator's existing activity and quiet/conversation hold
state controls a second private Core Audio process tap. That tap uses Core Audio's muted behavior for
the selected secondary processes; its IOProc discards buffers. It does not lower targets to a
percentage. Apple Music continues to use its existing pause or volume-duck path.

The first target-tap implementation crashed when Core Audio invoked an IOProc closure that had
inherited `MainActor` isolation. The crash report showed `_swift_task_checkIsolatedSwift` on
`com.apple.audio.IOThread.client`. The tap lifecycle now lives in a nonisolated, `@unchecked Sendable`
adapter; its callback captures no state and performs no work. Target bundle-ID roots include known
app helpers (including ego lite), matching only exact IDs and dot-delimited helper IDs. Safari is
excluded because `com.apple.WebKit` is shared.

- `./scripts/build.sh --no-sign` → passed; the menu bar app bundle built. After the final build,
  `open build/Oreja.app` launched PID 50746; `vmmap` reported a 31.0 MB physical footprint and
  `lsof` showed all three Oreja frameworks loaded.
- `./scripts/test.sh` → 87 passed, 0 failed, 391 assertions. Added coverage for target settings
  round-trip and overlap removal, Safari target exclusion, exact/helper-ID matching, including ego
  lite and ChatGPT roots, plus target-mute ownership through speech and the quiet interval.
- Controlled adapter smoke check: the `com.oreja.fixture` audio process was targeted; the muted tap
  started and restored without a crash. The rebuilt app also launched with all three Oreja frameworks
  loaded. This checks Core Audio lifecycle, not audible attenuation.
- Live ChatGPT + Apple Music + secondary browser/app audio was not run for this branch. Whether
  YouTube/browser output is actually muted and restored during ChatGPT speech remains unverified.
- No deployment, publication, or release was performed.

## Finder launch opens Settings (2026-11-15)

The user reported that the app could not be opened. The built bundle was valid and not crashing;
the menu-bar-only app did not give returning users a visible surface on direct launch. `AppDelegate`
now opens Settings after bootstrap for returning users; first-run users continue to receive onboarding.

- `./scripts/test.sh` → 89 passed, 0 failed, 422 assertions.
- `./scripts/build.sh` → passed and produced a valid ad-hoc signed `build/Oreja.app`.
- Relaunched the rebuilt bundle with `open build/Oreja.app`. System Events found the `Oreja Settings`
  window at 820×672; `vmmap` reported a 52.4 MB physical footprint and `lsof` showed all three
  Oreja frameworks loaded. This confirms the app launched and its Settings window was created.
- `git diff --check` → passed.
- No release or external announcement was made. Browser playback remains experimental pending live
  browser and interruption acceptance checks.

## 0.4.0 release acceptance (2026-11-15)

- The maker reported successful real playback testing with browser audio and confirmed the behavior
  works in their setup. The exact browser, website, playback mode, and interruption sequence were
  not specified in the report; this is user-reported acceptance, not an independently reproduced
  result.
- `./scripts/test.sh` → 89 passed, 0 failed, 422 assertions. `./scripts/build.sh` passed; the
  rebuilt 0.4.0 app opened Settings, had a 51.7 MB physical footprint, and loaded its Core, Audio,
  and Media frameworks.
- `codesign --verify --deep --strict build/Oreja.app` → passed. `CFBundleShortVersionString` is
  0.4.0 and `CFBundleVersion` is 7.
- `hdiutil create` built `build/Oreja-0.4.0.dmg`; `hdiutil verify` reported a valid checksum. The
  site download copy has the same SHA-256:
  `229cc6b648ead40ab6c6ab6828ee0aa8f90d5d101eb43a670a9f69d60f237f83`.
- Browser playback remains labeled experimental because browser and protected-player coverage is
  not universal. Supported scripting adapters are Safari, Chrome, Edge, Brave, Arc, and ego lite;
  Firefox and Internet Explorer are unavailable targets.

## User speech also mutes secondary apps (2026-11-15)

Follow-up: the user reported that AI speech muted the selected secondary app, but their own speech
did not. `pauseWhileISpeak` was enabled in the saved settings. The coordinator now tracks microphone
activity explicitly for target muting, including when the primary AI monitor is unavailable; the
existing microphone activity path still owns the music pause/duck decision.

- `./scripts/test.sh` → 87 passed, 0 failed, 391 assertions. Added a regression case for user speech
  keeping targets muted without a valid AI monitor.
- `./scripts/build.sh --no-sign` → passed.
- Real microphone speech causing a secondary app to mute was not run. This is an automated state
  check, not a verified live microphone-to-browser result.

## Mode-aware browser targets and Settings organization (2026-11-15)

Browser targets now use per-browser Apple Events scripting for standard HTML audio/video elements.
Safari uses its `do JavaScript` command; ego lite and the selected Chromium-family browsers use the
`execute ... javascript` command. Pause resumes only elements Oreja paused, without seeking. Ducking
tracks the applied level so restoration can preserve a user's volume adjustment. Tab execution errors
are counted and sent to Oreja diagnostics. Other selected apps continue to use the Core Audio mute
adapter.

- `./scripts/test.sh` → 88 passed, 0 failed, 411 assertions. New coverage checks browser dialect
selection, AppleScript argument escaping, failure counts, duck level generation, playback override
handling, and that pause scripts do not seek.
- `./scripts/build.sh --no-sign` → passed; `packaging/Info.plist` passes `plutil -lint`.
- The installed ego lite and Chrome scripting dictionaries were inspected; browser media behavior
was not exercised with live tab audio. Safari, Edge, Brave, and Arc adapters were not run against
their applications. ChatGPT speech, user microphone speech, and audible pause/duck/restore remain
unverified for the browser adapter.
- The final rebuilt app launched with three Oreja frameworks loaded and a 25.5 MB physical footprint.
- Settings were reviewed from source and reorganized into Audio, Playback, Automation, and Privacy
pages. A rendered click-through was not completed: the native settings window could not be opened
through the available desktop automation session.
- Firefox has no tab-control adapter and is unavailable as a secondary target. Internet Explorer
is not a macOS target supported by Oreja. No deployment or publication occurred.

## Browser playback target and Settings repair (2026-11-15)

The feature branch now separates interruption sources from playback targets. Browser selection and
the `All supported browsers` / `Active browser only` scope are in Playback settings; browser apps are
no longer selected in the generic app-target list. Legacy browser selections migrate to the
experimental Browser target without expanding to all browsers. Settings uses fixed section
navigation and a fixed page header with one scrollable content pane. Playback, Automation, and
Privacy were opened in the rebuilt app and visually inspected.

- `./scripts/test.sh` → 89 passed, 0 failed, 422 assertions. Coverage includes separate browser
  target migration, scope persistence, initially-playing media selection, and distinct playback and
  volume override states. Browser adapter checks generate scripts; they do not exercise a browser.
- `./scripts/build.sh` → passed. `open build/Oreja.app` launched PID 72765; `vmmap` reported a 26.9 MB
  physical footprint and `lsof` showed `libOrejaCore`, `libOrejaAudio`, and `libOrejaMedia` loaded.
- YouTube, Spotify Web, multiple simultaneous tabs, manual browser pause/resume, overlapping browser
  interruptions, and real ChatGPT Voice were not tested. Browser control remains experimental in
  this branch. Firefox has no adapter; Spotify playback control is not implemented. Internet
  Explorer is unavailable on macOS.
- No deployment, publication, or release was performed.

## v0.4.0 repair: lifecycle, honest capabilities and attribution (2026-11-21)

Worktree: `/Users/mac/orca/workspaces/oreja/oreja-v040-repair` (tag `v0.4.0`, commit `8313abd`).
This section records the repair built on the two completed dependency audits (Codex lifecycle/media
audit and the read-only Core Audio / API audit).

### Evidence levels used here

- **L0 — user report.** The person says they observed it; not reproduced by this agent.
- **L1 — deterministic test.** Executed by `./scripts/test.sh`; no hardware dependency.
- **L2 — build / static.** Compiles and/or inspected source; no live behavior claimed.
- **L3 — live local.** Executed and observed on this Mac in this worktree; command recorded.
- **L4 — not executed.** No pass is claimed.

### Commands actually run

| Command | Result | Level |
| --- | --- | --- |
| `./scripts/test.sh` | **100 passed, 0 failed, 486 assertions** (was 89/0/422 at v0.4.0) | L1 |
| `./scripts/build.sh --probe` | OrejaCore, OrejaAudio, OrejaMedia, menu-bar app and `oreja-probe` compiled; ad-hoc codesign valid on disk and satisfies its designated requirement | L2 |
| `open -n build/Oreja.app` | final build started PID 78478; `vmmap -summary` → physical footprint **54.5 MB**; `lsof -p` → `libOrejaCore.dylib`, `libOrejaAudio.dylib`, `libOrejaMedia.dylib` all loaded from this worktree's `build/Oreja.app/Contents/Frameworks`. Earlier rebuild launched PID 68119 at 53.1 MB. All test-launched instances were terminated; the person's `/Applications/Oreja.app` instance was untouched. | L3 |
| `./build/bin/oreja-probe --list` | 32 audio processes; `com.openai.codex.helper` pid 15739 `output=yes`, `com.openai.codex` (ChatGPT.app pid 723) `output=no`, `com.citrolabs.ego.helper` pid 6261 `output=yes` | L3 |
| `ps -axo pid,ppid,comm \| grep -i chatgpt` | ChatGPT desktop runs a large helper tree (`Codex (Aperitif)`, renderers, `codex-cli`), confirming the audio renderer is a helper rather than the main app process | L3 |

The extra instances launched for this check were terminated; the person's `/Applications/Oreja.app`
instance (pid 32872) was left untouched. No Apple Music command, TCC change, or settings write was
performed by this agent.

### Fixes and their deterministic coverage (L1)

- Activity aggregation now lives in `PlaybackCoordinator`. `monitoringFailed` and
  `sourceInvalidated` clear only the AI half, so a retry's next real onset issues a new pause;
  tests 23 and 24 cover recovery and the AI-fails-while-mic-active case.
- Microphone activity is routed through `setActivity(..., source: .user, levelDB:)`, which does not
  require a valid AI source. Tests 21 and 22 cover mic-only pause and mic-only duck with
  `sourceIsValid == false`. Test 25 covers mic failure while AI remains active. Test 26 covers an
  automation off/on cycle plus teardown without stranding an owned pause.
- `shouldMuteTargetAudio` keeps the previously tested release semantics while allowing mic-only
  interruptions; the existing mute test still passes.
- `AppModel` re-enables the opted-in microphone monitor when automation is switched back on. The
  core half (mic activity after an automation toggle) is covered by test 26; the AppKit monitor
  restart itself is L2 only because `apps/macos` has no test target in this harness.
- `PlaybackTargetCapability` tests assert Apple Music is supported, and that Spotify and Browser
  return explicit reasons. `coProcessWarning` tests assert a browser source still controls Apple
  Music while warning that ChatGPT Web and browser music in the same process cannot be separated.
- `AudioProcessDiagnostics.describe` tests assert the exact helper bundle, pid and output state are
  present. The monitor now logs the tapped process set, so a future Desktop-only Voice run can
  attribute an onset to a process instead of guessing from a combined source.

### Five-path acceptance matrix

| # | Path | Evidence | Result |
| --- | --- | --- | --- |
| P1 | Selected ChatGPT audio detected; ChatGPT stays audible | L3 process inventory shows the desktop renderer is `com.openai.codex.helper` (pid 15739) while the main app has no output; L0 user reports both Desktop and Web speech lower Music | Detection path plausible and user-observed; not reproduced under an isolated Desktop-only Voice run by this agent |
| P2 | Apple Music duck to configured % | L0 user reports Desktop and Web speech individually lower Music; L1 duck tests pass; commands | Live duck is **user-reported only (L0)**; no live duck was executed by this agent |
| P3 | Apple Music pause/resume | Historical L3 measurements in this document (~190–280 ms per command); no new live run | Previously verified on a local track; not re-run in this repair |
| P4 | Spotify duck or pause | Audit L2: Spotify.app absent, no official dictionary available locally; Web API needs Premium, an OAuth grant and a remote service, all excluded by project rules | **Hard blocker — not implemented, not claimed** |
| P5 | Whole-browser duck or pause | Audit L2: no supported public per-process gain or pause/transport API; Chrome/Safari dictionaries only expose per-tab JavaScript (excluded); tap mute would silence the conversation and is not a duck | **Hard blocker — browser playback target is marked unavailable**; no mute or per-tab JS path is used |

### Uncovered gaps and warnings added

- Desktop AI + music playing in a browser cannot be lowered or paused: no supported target API
  exists (P5). Settings now states this explicitly.
- ChatGPT Web + music in the same browser share one audio process and cannot be separated. The
  user chose **"Impedir la combinación"**, so this is now a refusal, not only a warning:
  `PlaybackTargets.canAddSource` rejects adding a browser source while the Browser media target is
  on, and `canEnableBrowserPlayback` rejects enabling that target against an already-selected
  browser source. `toggleSource` and `setBrowserPlaybackEnabled` enforce it in the real settings
  path, and `AudioSourcePicker` disables the conflicting new selection with an explicit reason.
  Neither side is silently deselected; an already-selected browser source stays toggleable so it
  can be removed, and it remains fully valid for controlling Apple Music when the target is off.
  Repository tests cover both rejection directions (L1). The Browser media target itself is still
  unavailable, so no live selection of it was possible here.
- The user's baseline live interval showed combined monitor reaction and manual Music starts being
  honored. That does **not** prove which source triggered, so Desktop-only acceptance is still open.
  A future isolated run should select only `com.openai.codex`, start a Voice reply, and read the new
  `Tapped audio processes:` diagnostic line to correlate the onset with a pid.
- Not executed (L4): isolated Desktop-only Voice session, clean-account Apple Music control, any
  Spotify or browser playback control, real microphone ducking, notarization, and measured latency.

## Remaining public-route investigation: whole-browser playback target (2026-11-21)

Status: **OPEN — requirement not met, browser E2E not passed.** The user's requirement stands: while
ChatGPT Desktop speaks, music playing in a browser must duck to the configured percentage or
pause/resume per settings. Disabling the Browser media target and refusing the ChatGPT Web +
Browser media combination are safety decisions, **not** completion of that requirement. No supported
whole-browser control route was found; nothing in this section should be read as a pass.

### Local SDK evidence (all L2: static header/dictionary inspection, no live control)

| Command | Observed result |
| --- | --- |
| `grep -rn 'kAudioProcessProperty' .../CoreAudio.framework/.../Headers` | The Process audio object exposes only `kAudioProcessPropertyPID`, `BundleID`, `Devices`, `IsRunning`, `IsRunningInput`, `IsRunningOutput`. There is **no process gain, volume, mute or transport property**. |
| `sed -n '1944,1986p' .../AudioHardware.h` | Header doc confirms those six properties only: PID, bundle ID, devices, and three running flags. |
| `grep -rn 'kAudioDevicePropertyMute' .../CoreAudio.framework/.../Headers` | Mute exists only as `kAudioDevicePropertyMute` on **AudioDevice** (the whole device), not per process. Using it would mute every app and is a forbidden system/substitute control. |
| `grep -n -A 24 'CATapMuteBehavior' .../CATapDescription.h` | `CATapUnmuted` captures and still sends audio to hardware; `CATapMuted` captures but sends **no** audio from the process to hardware; `CATapMutedWhenTapped` suppresses hardware output while another client reads the tap. These are capture-path controls, not gain. |
| `grep -n -A 6 'AudioHardwareCreateProcessTap' .../AudioHardwareTapping.h` | Process taps are public from macOS 14.2. They create a tap object; they do not set another process's output level or transport state. |
| `grep -n 'addTarget\|removeTarget' .../MediaPlayer.framework/.../MPRemoteCommand.h` | `MPRemoteCommandCenter` is receive-only: an app calls `addTarget:action:` / `addTargetWithHandler:` to **handle** remote commands sent to it. There is no API to send a command to an arbitrary app. |
| `find .../SDKs/MacOSX.sdk/System/Library/Frameworks -iname 'MediaRemote*'` | No result. The framework that would issue system media commands is not in the public SDK; using it would be a private API. |
| `grep -o -i 'name="[^"]*"' /Applications/Google\ Chrome.app/Contents/Resources/scripting.sdef \| grep -i -E 'play\|pause\|volume\|javascript\|execute'` | Only `execute` / `javascript`. No media transport or volume command. |
| same on `/Applications/Safari.app/Contents/Resources/Safari.sdef` | Only `do JavaScript`. No media transport or volume command. |
| same on `/System/Applications/Music.app/Contents/Resources/com.apple.Music.sdef` | `pause`, `play`, `playpause`, `resume`, `sound volume`. This is why Apple Music is the only supported target. |

### Routes considered and rejected

1. **Per-process gain/volume property** — does not exist on the Process audio class (see above).
2. **App-level media transport aimed at a browser** — `MPRemoteCommandCenter` receives commands for
   the calling app only; there is no public sender API and no way to address another app's Now
   Playing session. `MediaRemote` is private. Global media-key event synthesis is not browser
   specific and would also hit Apple Music and other players, so it is excluded.
3. **Browser Apple Events / scripting dictionary** — Chrome and Safari expose only per-tab
   JavaScript, which the user forbids; it also cannot guarantee session ownership across tabs.
4. **Tap with `CATapMuted` plus re-rendering the captured audio at the configured gain through an
   aggregate device / output AudioUnit** — the only conceivable public-primitive route. It is **not
   implemented and not claimed**, for these concrete reasons:
   - It requires suppressing the browser's real output (`CATapMuted` / `MutedWhenTapped`) and playing
     a copy from Oreja. If Oreja crashes, is force-quit, or loses the device, the browser's audio can
     be left silent — a worse outcome than not ducking. There is no OS-owned restore guarantee.
   - It cannot distinguish browser media from a browser conversation without per-tab scripting. For
     ChatGPT Web plus music in the same browser it is therefore unusable, and for other browsers it
     would duck unrelated audio (meetings, alerts) in the same process.
   - It inserts an app-mediated real-time path with added latency, device-change, sleep/wake and
     sample-drop handling that has not been designed, implemented or measured here. No latency or
     correctness evidence exists.
   - Suppressing the original output is a mute-based substitute, which the user explicitly ruled out.

### Consequence for acceptance

- **Open requirement (L4 here):** ChatGPT Desktop speech + browser music → configured duck or
  pause/resume. No supported route was found; do not mark this passed. A future implementation would
  need a new public per-process/per-session gain or transport API, or a browser-provided extension
  API that does not rely on per-tab JavaScript and can prove ownership and restore; neither exists
  in the audited SDK or browser dictionaries.
- The user-reported live ducking of Apple Music by ChatGPT Desktop and ChatGPT Web remains **L0
  (user report)**. It does not establish browser-target control.
- Browser target capability continues to report `unavailable` from `PlaybackTargets`; the
  deterministic test covering that reason still passes. No browser playback E2E was executed.

## v0.4.0 microphone speech report (2026-11-22)

Report: Apple Music ducks to 11% when ChatGPT Desktop speaks, but not when the user speaks. Settings:
`pauseWhileISpeak=true`, `automationEnabled=true`, `interruptionMode=duck`, `duckVolumePercent=11`,
`microphoneSensitivity=normal`. Default input: Sony Bluetooth, mono, 16 kHz. The default output was
not recorded in the report.

### Code findings (read, not measured)

- Sample path: the tap delivers Float32, `LevelSampler` computes RMS over 50 ms frames, and
  `AudioMath.decibels` converts with `10·log10(mean square)`, which is dBFS for RMS. The conversion is
  correct.
- Gate: `PlaybackCoordinator.setActivity(_:source: .user)` rejects a voice onset when the default
  output is built-in speakers and no AI interruption is in progress (`userSpeechMayStartAlone`). The
  rejection was silent before this change, so the logs cannot distinguish it from a missed onset.
  Test 27 asserts this rule on purpose; it guards against speaker-to-microphone feedback.
- Threshold history: commit `ac96c97` set the normal microphone activation to −25 dBFS after live
  Sony-mic idle spikes in the high −30s re-paused Music (`docs/test-evidence.md`, "Human microphone
  path"). Commit `b09e63f` changed normal to −35 dBFS, citing built-in-mic numbers (room median −46,
  speech median −26) that do not appear in any evidence file. The −35 value has no Sony-mic
  measurement behind it.
- The −35 threshold is more permissive than −25, so it cannot explain a miss by itself.

### Not established by the report

- No microphone level in dBFS was present in the logs, so it is not known whether speech reached the
  −35 dBFS threshold. No output-device transport was logged either. The report alone does not
  separate "speech below threshold" from "output is built-in speakers, so the gate rejected the
  onset".

### Change made

- `PlaybackCoordinator.setActivity`: a rejected voice onset is logged at info level ("Your voice was
  heard but did not pause music…"). Covered by test 27 and test 27b.
- `AppModel.startUserSpeechMonitoring`: the start message now states whether the default output is
  built-in speakers, which decides whether the voice can start a pause.
- `MicrophoneLevelWindow` plus `AudioActivityEvent.microphoneLevels`: once per second the microphone
  monitor reports peak dBFS, mean dBFS and the frame count, plus the activation threshold. It keeps
  numbers only; no samples are stored. `AppModel` records these only when verbose diagnostics are on.
  A window with zero frames means the microphone delivered no audio. Covered by the detection test
  "microphone level window reports peak, mean and frame count once per second".
- The threshold is unchanged. The evidence does not show which value is correct for this input.

### Verification executed

- `./scripts/test.sh`: 104 passed, 0 failed, 508 assertions (baseline 102; two added).
- `./scripts/build.sh`: built `build/Oreja.app`, ad-hoc signed; `valid on disk`.
- `./scripts/build.sh --probe` was refused by the permission layer and was not run. The
  `tools/AudioProbe` and `tools/IntegrationHarness` switch cases were edited but not compiled.
- Not executed: launching the built app, any real speech or microphone run, verbose-log capture,
  and any check of the default output device. No microphone level was measured.

### Live verification still needed

1. Enable verbose diagnostics, speak into the Sony input, and read the `Microphone level, last second`
   lines. Peak above −35 dBFS means the threshold is not the cause. Peak below −35 with clear speech
   means the Sony input is too quiet, and the threshold choice is the question.
2. Read the start message: "default output is built-in speakers" means the voice gate is rejecting
   onsets by design. Switch the output to headphones and repeat.
3. Only after 1 and 2 are known, decide whether the −35 normal value should move. Do not adjust it
   from this evidence alone.

## 2026-11-22 — Browser music as a lowered "other app" (case 2: ChatGPT Desktop + YouTube in a browser)

Change: browsers other than Safari can be selected as other apps to interrupt. Lower mode mutes the
browser's process output with a Core Audio process tap and plays the tapped audio to the default
output device at the duck level (`TargetAudioRenderer`); pause mode silences the browser, because a
browser exposes no pause control Oreja can reach without per-tab scripting. The previous browser
target (per-tab JavaScript, refusal rules, "Browser (unavailable)" section) was removed first.

Executed:
- `./scripts/test.sh`: 108 passed, 0 failed, 502 assertions (renderer channel mapping, ramp,
  non-interleaved output, empty input, browser targets kept/Safari dropped, gain per mode).
- Real audio, harness (`scratchpad/tap-harness`) driving `ProcessAudioTargetMuteController` against
  YouTube playing in ego lite (`com.citrolabs.ego.helper`, pid 6261, output=yes). Original onset level
  measured by `oreja-probe --bundle com.citrolabs.ego`: −15.4 dBFS. Replayed audio from the harness
  process at gain 0.15: no activity at a −25 dBFS threshold, activity at −45 dBFS (onset −41.0 dBFS).
  This brackets the replay well below the original; it is not an exact gain measurement.
- Full app path with `OrejaFixture` as a scripted source (notification filter off for the run only):
  log shows "Lowering ego lite to 11% during speech." at tone start and "Restored ego lite." after the
  quiet interval; Oreja was an audio process with output=yes during the tone. YouTube had stopped by
  then (ego helpers output=no), so this run proves the control path, not audible lowering.

Not executed / not proven:
- A person hearing YouTube lowered while ChatGPT Desktop speaks. Needs the user.
- That the original browser output is inaudible while lowered (mute behavior) — only inferred from
  the API contract and the absence of an error.
- Safari as a target (excluded: shared WebKit audio process).
- Case 3 (ChatGPT Web + Apple Music) and case 4 (ChatGPT Web + YouTube in the same browser).
  Detection of ego lite audio through its helper tap did work in this session (YouTube onset at
  −15.4 dBFS), which is the same path ChatGPT Web would use, but no ChatGPT Web reply was measured.

## 2026-11-22 — Settings redesign, music players as targets, live browser lowering through the app

Changes: "Listen to" (Audio) and "Lower these apps" (Playback) are separate lists; the lowered list
now shows browsers (it hid them before, so a browser could never be chosen) and music players
(Spotify, VLC; Apple Music stays native). Toggles align right, captions sit above cards, the sidebar
icon column is fixed width, slider tick rows removed. Added: Test interruption (coordinator
`.preview` source), permission status rows including Microphone, Open diagnostics / Show log file,
live Apple Music status and connection-check results, a warning with a one-click move when a
selected source is playing media. Version is stamped from git by `scripts/build.sh`
(`0.4.0`, build 42, `b09e63f-modified`, 1 commit after v0.4.0) instead of the hard-coded plist.
Real-time fixes from review: raw-pointer renderer, no reference counting in the IOProc,
time-based ramp (0.2 s), a pending release is not restarted, "Lowering" is only logged when audio
is actually replayed.

Executed:
- `./scripts/test.sh`: 111 passed, 0 failed, 548 assertions.
- Build launched: PID 71150, footprint ~51 MB, three Oreja dylibs loaded.
- Settings pages captured with Orca computer use; layout reviewed on screen.
- Live, real app, user's YouTube in ego lite (`com.citrolabs.ego.helper` output=yes), ego lite moved
  to "Lower these apps" through the new UI, output Sony headphones: microphone speech triggered
  "Lowering ego lite to 11% during speech." (23:40:57Z), Oreja rendered audio (probe on Oreja pid:
  activity at −40.1 dBFS), then "Restored ego lite." (23:41:00Z) and Oreja output ended (−100 dBFS).
  Repeated on later phrases.

Not executed / not proven:
- The person confirming by ear that YouTube dropped and came back.
- ChatGPT Desktop speech lowering ego lite (same path as the microphone run; not observed).
- The Test interruption button clicked live (unit-tested through the coordinator only).
- Spotify/VLC lowering (not installed here).

## 2026-11-22 — Status names the speaker; microphone follows the voice session

- Status line (menu bar and Settings sidebar) now comes from the coordinator's per-source activity:
  "ChatGPT is speaking", "You are speaking", "You and ChatGPT are speaking", "Testing the
  interruption"; with several selected apps it says "a selected app" (their audio is measured
  together, so the app is not guessed). Unit-tested; `./scripts/test.sh`: 113 passed, 0 failed.
- Root cause of "it said ChatGPT while I spoke": Oreja listened on the MacBook mic while the person
  spoke into the Sony headset. Measured with ffmpeg at the same moment: Sony headset mic speech
  peaks −21 to −25 dBFS (above the −35 threshold); MacBook mic max −40 dBFS (below it). The earlier
  conclusion that the headset mic "delivers silence" came from a measurement taken while nobody spoke.
- New rule (`InputDeviceSelection`): headset mic while another app is already recording (voice
  session or call: the headset is in call mode anyway), otherwise the built-in mic so Oreja never
  switches the headset into call mode itself; re-checked every 3 s. Live: with the ChatGPT voice
  session open, the log shows "Listening for your voice on Sony Headphones."
- In the window where the label read "ChatGPT is speaking" after the fix (23:49:31–36Z) the headset
  mic peaked at −70 to −45 dBFS, i.e. the person was not speaking then. "You are speaking" from a
  real person into the headset has not been observed yet.
