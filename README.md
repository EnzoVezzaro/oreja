# Oreja de Van Gogh

**Your AI talks. Your music listens.**

Oreja is a tiny macOS menu bar companion with one job: when the selected AI app starts speaking,
Oreja either pauses Apple Music or lowers its volume, depending on your chosen mode. When the app
goes quiet, Music resumes or its original volume returns exactly where it left off.

- It runs alongside ChatGPT. It does not replace it, proxy it, or change your account.
- It needs no OpenAI API key, no account, and no network connection.
- It never records, transcribes, stores, or uploads conversation audio. Only a dBFS level is
  derived from the selected app's output, in memory, and discarded immediately.
- It is an independent project. It is not affiliated with or endorsed by OpenAI or Apple.

## Download

[Oreja 0.2.0](https://github.com/EnzoVezzaro/oreja/releases/latest) is a disk image for macOS 14.2
or newer, also served from [the landing page](https://oreja-tau.vercel.app/). It is ad-hoc signed
and not notarized, so the first launch on another Mac needs one Gatekeeper approval (System
Settings › Privacy & Security › Open Anyway). What changed: [CHANGELOG.md](CHANGELOG.md).

Status: **macOS MVP built and working on the development machine** (macOS 26.6.2, Apple M2). The
Core Audio capture path and real Apple Music pause/resume have been exercised end to end against a
controlled audio fixture. A live **ChatGPT Voice session has not** been run; see
[Verification](#verification) for exactly what was and was not executed.

## How it works

```
ChatGPT output audio ──► Core Audio process tap ──► level analysis ──► coordinator
                                                                          │
Apple Music playback state ◄── Apple Events ◄── pause / resume commands ◄──┘
```

Oreja taps the **output** of the selected application's Core Audio processes (macOS 14.2+),
unmuted, so ChatGPT keeps playing normally while Oreja listens to a copy. The tap is private,
targeted at that application's processes (including its helpers), and torn down when monitoring
stops. Music is controlled with Apple Events against the Music app, which Oreja never launches on
its own.

The decision to pause or resume lives in one deterministic state machine
(`packages/OrejaCore/Sources/OrejaCore/PlaybackCoordinator`) with no AppKit, no Core Audio, and no
AppleScript, so it is fully unit-tested. Platform code is behind the ports in
`packages/OrejaCore/Sources/OrejaCore/Protocols`.

Read [docs/architecture.md](docs/architecture.md) for the full design.

## Requirements

- macOS 14.2 or newer (Core Audio process taps). Developed and tested on macOS 26.6.2, arm64.
- The ChatGPT desktop app (`com.openai.chat`, `com.openai.chatgpt` or `com.openai.codex`) **or**
  Safari/Chrome running ChatGPT on the web (experimental; captures the whole browser process).
- The Music app for playback control. An Apple Music subscription is not required by Oreja, but
  Music must be the app that is playing.
- To build: Command Line Tools (`xcode-select --install`) or Xcode. No third-party dependencies.

## Build and run

```bash
./scripts/build.sh            # builds build/Oreja.app, generates the icon, ad-hoc signs it
open build/Oreja.app
```

Add `--probe` to also build the `oreja-probe` audio diagnostic, `--harness` to build the real
capture → Music measurement harness, and `--no-sign` to skip signing.

The first launch opens a six-step setup: welcome, AI source, music source, audio-capture
permission, live test, finish. After setup the app lives only in the menu bar (`LSUIElement`).
Onboarding runs once per install; to see it again, quit Oreja and delete its defaults with
`defaults delete app.oreja.van-gogh`.

To run the automated suite:

```bash
./scripts/test.sh             # 54 tests, 0 failures
./scripts/test.sh resume      # filter by test name
```

This machine has Command Line Tools only and its SwiftPM manifest library is broken, which is why
the scripts call `swiftc` directly. A canonical `Package.swift` is included for Xcode/SwiftPM
users; `swift build` and `swift test` need a full Xcode toolchain and are not used here.

### Build artifact

`build/Oreja.app` — ~2.9 MB, ad-hoc signed (no hardened runtime, because ad-hoc signatures have no
team identity for library validation) with these entitlements:
`com.apple.security.device.audio-input`, `com.apple.security.automation.apple-events`. It is **not
notarized**; see [docs/distribution.md](docs/distribution.md).

## Permissions

Oreja asks for two macOS permissions, each with a specific purpose string:

| Permission | Why | Where |
| --- | --- | --- |
| System audio recording | Read the selected app's output level through a Core Audio process tap | System Settings › Privacy & Security › Screen & System Audio Recording |
| Automation (Music) | Pause, resume, or adjust the Music app's volume, depending on the selected mode | The macOS prompt on first control, then System Settings › Privacy & Security › Automation |

No microphone is needed by default. The optional “Pause while I speak” setting uses microphone level
only; Oreja does not request screen content, accessibility, full disk, contacts, or network access.
Details and reset commands: [docs/permissions.md](docs/permissions.md).

## Using Oreja

- **Automation switch** in the menu bar panel enables or disables coordination. Turning it off while
  Oreja owns a pause or volume change restores Music first.
- **Conversation hold** (Settings, 0–60 s, default 0 s) can keep music interrupted through the
  silent stretches while the assistant works on an answer. Set it above zero when you want that
  conversation-wide behavior; otherwise Music returns after the resume delay.
- **Resume delay** (Settings, 0.3–3.0 s, default 0.8 s) is how long the AI must stay quiet before
  music resumes when the conversation hold is off. Both are layered on top of the detector's 0.25 s
  silence window.
- **Pause while I speak** (off by default, needs the microphone) keeps the music paused while you
  answer. When enabled, the microphone can also start a pause when the person speaks first;
  headphones are recommended so music does not feed back into the microphone.
- **Manual control always wins.** If you pause Music yourself, Oreja will not resume it. If you
  resume Music while ChatGPT is speaking, Oreja releases its claim and will pause again the next
  time ChatGPT speaks.
- **Resume delay across sentence gaps** is handled by hysteresis: short gaps inside a response keep
  music paused.
- **Quitting** while Oreja owns a pause resumes the music before exit. If Oreja crashes, the pause
  journal restores playback on the next launch only when the same track is still paused.

The menu bar shows one state at a time: off, looking for the source, monitoring, ChatGPT speaking,
waiting for silence, music paused by Oreja, resuming, suspended, permission required, or needs
attention.

## Verification

Executed on this machine (macOS 26.6.2, Apple M2, Swift 6.3.3):

- ✅ **54/54 automated tests pass** (283 assertions): pause, resume, stale-state recovery, sentence gaps, conversation hold, volume ducking, user-first speech pause, manual pause and resume, process exit, Music exit, permission revoked, device change, rapid responses, sleep/wake, ownership reconciliation, quit restoration, delayed commands, command-failure limits, detector thresholds/hysteresis, AppleScript parsing, one-round-trip command scripts, settings, journal recovery, and reactive playback settings.
- ✅ **App bundle builds, signs, and launches**: the menu bar app stays resident, maps only its own
  `Contents/Frameworks` dylibs, and idles at 0.0–0.1% CPU with a ~37–54 MB physical footprint.
  A packaging bug that made the app abort in dyld at launch was found and fixed; see
  [docs/test-evidence.md](docs/test-evidence.md#packaging-bug-found-by-this-check).
- ✅ **Core Audio process tap capture works**: the probe tapped a controlled `say` process and
  reported `▶ activity started at -20.8 dBFS` followed by `■ activity ended at -100.0 dBFS`.
- ✅ **Real Apple Music pause/resume works** (seven consecutive runs of the integration harness):
  Music paused on tone onset, stayed paused, then resumed the same track after the 800 ms quiet
  interval; exactly one pause and one resume per run; a separate pause test froze
  `player position` (1.041 → 1.046 s over a 2 s pause) and continued from it.
- ✅ **250 ms latency target met**: each command is now one Apple Event that pauses and reports the
  new state, with compiled scripts cached. Detected onset → music actually paused measures
  **187–201 ms** (was 570–687 ms), and resume 1654–1721 ms end to end including the deliberate
  250 ms detector window and 800 ms quiet interval.
- ✅ **Process discovery works** against real Core Audio process objects, including the installed
  ChatGPT application (`/Applications/ChatGPT.app`, bundle `com.openai.codex`) and its helpers.
- ❌ **Not executed: a real ChatGPT Voice session.** Starting one requires a signed-in human
  session, and the desktop app exposes no scriptable window or Voice command. Oreja's ChatGPT audio
  path is therefore unverified against live ChatGPT output.
- ❌ **Not measured: CPU/battery impact, Bluetooth/AirPods/device switching, and ChatGPT-specific
  end-to-end latency.** The harness numbers above use a local fixture and the default output device.
- ❌ **Not notarized.** No Developer ID credentials were available. Ad-hoc signing only.

Full evidence, commands, and raw results: [docs/test-evidence.md](docs/test-evidence.md).
Capability matrix and remaining unknowns: [docs/feasibility.md](docs/feasibility.md).

## Repository layout

```
apps/macos/                     SwiftUI menu bar app, onboarding, settings, diagnostics
packages/OrejaCore/             Domain, ports, playback coordinator, settings (no platform APIs)
packages/OrejaAudio/            Core Audio process discovery, taps, level analysis, detector
packages/OrejaMedia/            Apple Music Apple Events adapter, mock provider
Tests/OrejaTestRunner/          Executable test suite (no XCTest runtime required)
tools/AudioProbe/               Developer capture probe (--list / --bundle / --pid)
tools/IntegrationHarness/       Real tap → coordinator → Apple Music measurement harness
tools/IconBuilder/              Generates AppIcon.icns from the brand mark
packaging/                      Info.plist, entitlements
scripts/                        build.sh, test.sh
docs/                           Architecture, feasibility, permissions, compatibility, brand…
site/                           Static landing page and documentation page (no build step)
```

## Privacy

Local only. No audio buffers are written to disk; only RMS levels exist, for milliseconds, in
memory. No prompts, responses, transcripts, track names, or account data are collected. Settings
and the pause journal live in `UserDefaults`; the diagnostic log is an in-memory ring buffer.
There is no analytics SDK and no server. Full text: [docs/privacy.md](docs/privacy.md).

## Limitations

- macOS 14.2+ only. iOS is researched, not implemented: [docs/ios-strategy.md](docs/ios-strategy.md).
- The detector identifies *output activity*, not verified speech. ChatGPT notification sounds or
  other audio from the same process can pause music. This is documented behavior, not a promise of
  semantic speech detection.
- Browser-based ChatGPT is experimental and captures every tab in that browser.
- The app is ad-hoc signed and unnotarized, so another Mac will require a Gatekeeper bypass.
- The name has not been cleared for trademark use; do not publish under it without a search.

## Roadmap

See [docs/roadmap.md](docs/roadmap.md). Next milestone: a supervised live test against a real
ChatGPT Voice session and Apple Music, including measured pause/resume latency and a device matrix.

## Brand and site

**Website: https://oreja-tau.vercel.app** — landing page, documentation and the current DMG.

One brand system across the app and the site: warm white paper, charcoal ink, a straw-hatted pixel
Vincent with a bandaged ear, and coral for the listening light. Palette, type scale, voice rules,
mark and character usage are in [docs/brand.md](docs/brand.md); the tokens live in
`apps/macos/Theme.swift` and `site/styles.css` and must change together.

Vincent's five frames are generated, not drawn by hand: `python3 scripts/vincent-sprite.py` writes
`site/assets/oreja-vincent.png`, which the website animates as a sprite sheet and `scripts/build.sh`
copies into the app bundle. Clicking him in the app plays the fifth frame: the bandage leaves his
head and he shouts.

The landing and documentation pages are static and need no build step:

```bash
open site/index.html                     # or:
python3 -m http.server 8000 -d site      # http://localhost:8000
```

See [site/README.md](site/README.md) for what is in the folder and the rules it follows.

## License

GPL-3.0-only — see [LICENSE](LICENSE). Repo Shield's [NOTICE](NOTICE) and [AI training policy](AI_TRAINING_POLICY.md)
document the repository's position on AI-training use without changing GPL's open-source rights.

See [TRADEMARKS.md](TRADEMARKS.md) for the project's name, logo and endorsement
position.

## More documentation

- [Brand guidelines](docs/brand.md)
- [Apple Music connection guide](docs/apple-music.md)
- [ChatGPT sources on macOS](docs/chatgpt-sources.md)
- [Test results log](docs/test-results.md) and [consolidated evidence](docs/test-evidence.md)
- [Landing and docs pages](site/README.md)
