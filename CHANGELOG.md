# Changelog

Notable changes to Oreja de Van Gogh. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow semantic versioning from the first signed release. Dates are the day the build was
made, not the day it was published.

## [Unreleased]

### Planned

- **Native pause for more players** where a supported control exists (today other players are
  lowered or silenced, not paused).
- **More app sources.** Add and verify more audio-source profiles as apps and their audio process
  identifiers change.

## [0.5.0] - 2026-11-22

### Added

- **Lower browsers and other players.** Playback › Lower these apps takes any app that plays audio:
  a browser with YouTube (Chrome, Edge, Brave, Arc, Firefox, ego lite), Spotify, VLC. While someone
  speaks it is lowered to the duck level, or silenced in pause mode, and ramped back afterwards. It
  works through a muted Core Audio process tap with the audio replayed at the chosen level: no
  browser setting, no page scripting, no system volume.
- **Your voice interrupts reliably.** Microphone thresholds were recalibrated against measured
  speech (Normal −35 dBFS). The monitor listens on the headset mic while a voice session or call
  already has it open, and on the Mac's own mic otherwise, so Oreja never switches a Bluetooth
  headset into call mode by itself. On the Mac's own speakers your voice only extends an
  interruption already in progress, so music from the speakers cannot pause itself.
- **Status names the speaker:** "ChatGPT is speaking", "You are speaking", "You and ChatGPT are
  speaking", in the menu bar and in Settings.
- **Test interruption** button: runs your setup for 4 seconds without waiting for an assistant.
- **Permissions at a glance:** audio recording, microphone and Music automation, each with its
  status and a button to the right System Settings pane.
- **Diagnostics shortcuts:** open the diagnostics window or show the log file; verbose mode records
  the microphone level once a second.
- A warning, with a one-click move, when an app selected as a source is playing media.

### Changed

- **Settings redesigned.** Audio is what Oreja listens to (apps, your voice, detection); Playback is
  what makes room (Apple Music, timing, Lower these apps). Compact app lists with search and "Show
  all apps", switches aligned in one column, explanations above the controls, live Apple Music
  status and connection-check results.
- **The version shown in the app is stamped from git** at build time (tag, build number, commit),
  so it always matches the build you are running.

### Removed

- The 0.4.0 per-tab JavaScript browser control and the rule refusing browser sources next to a
  browser target. Browsers are now lowered through process taps instead.

### Verified and limitations

- Automated suite: 113 tests passed, 557 assertions. App built, signed ad hoc and launched on
  macOS 26.6.2 (Apple M2).
- Live: the maker reported Apple Music lowering while ChatGPT Desktop spoke and while they spoke.
  YouTube in ego lite was lowered to 11% by a real voice onset and restored, observed in the app
  log and measured with the probe. Details: `docs/test-evidence.md`.
- Not measured: ChatGPT Web + Apple Music, Spotify and VLC (not installed on the test Mac).
- Other apps are lowered or silenced, never paused; a video keeps playing silently in pause mode.
  Safari cannot be lowered (shared WebKit audio process). ChatGPT Web and music in the same browser
  cannot be separated: use two browsers.
- Ad-hoc signed, not notarized.

## [0.4.0] - 2026-11-15

### Added

- **Separate interruption sources from playback targets.** Choose the apps Oreja listens to and
  independently choose playback targets. The optional Browser target controls standard HTML audio
  and video in supported scriptable browsers: Safari, Chrome, Edge, Brave, Arc, and ego lite. Choose
  all supported browsers or the active browser.
- **Browser interruption modes.** Pause media that was already playing when the interruption began
  and resume it at the same position, or lower its volume and restore it when the interruption ends.
  Oreja tracks its own changes and honors manual playback or volume changes.
- **User speech can interrupt selected targets.** When “Pause while I speak” is enabled, the same
  selected playback targets respond while the user talks.

### Changed

- **Settings reorganized.** Audio sources, playback targets, automation, permissions, and privacy
  controls are grouped into focused sections with clearer browser capability and permission guidance.
- **Direct launch opens Settings.** Returning users see the app's main window when opening Oreja
  from Finder; first-run onboarding is unchanged.

### Verified and limitations

- Automated suite: 89 tests passed, 422 assertions. App built and launched on macOS 26.6.2 (Apple
  M2). A user reported successful real browser playback testing; the exact browser, website, and
  interruption settings were not recorded in the test evidence.
- Browser control uses browser scripting permissions and standard HTML media elements. Some
  protected or custom players may not respond. Firefox has no adapter; Internet Explorer is not
  available on macOS. Spotify's native app is not a playback target.
- The build is ad-hoc signed and not notarized. See `docs/compatibility.md` and
  `docs/distribution.md` for support boundaries and installation details.

## [0.3.1] - 2026-11-10

### Fixed

- **The menu bar icon disappeared when automation was off.** The icon for that state used the SF
  Symbol `ear.slash`, which does not exist, so the menu bar drew nothing and only the clickable
  space remained. The same happened to "Looking for the AI source" (`ear.badge.questionmark`).
  The icons are now `speaker.slash` and `magnifyingglass`. A name the running macOS does not know
  now falls back to the ear instead of an empty image.

## [0.3.0] - 2026-11-10

Several audio apps at once, and the AI listener now comes back after sleep.

### Added

- **Real detection settings** in Settings → Detection: **The AI's voice** and **Your voice**
  (High / Normal / Low) move the actual activation thresholds — −55/−45/−35 dBFS for app output,
  −35/−25/−18 dBFS for the microphone — instead of only changing copy. Hysteresis stays a fixed
  10 dB, and changing a level restarts the tap immediately. The section replaces the previous
  single-toggle version.
- **Hooks**: a general automation surface in Settings → Hooks. Twelve of Oreja's own events (speech
  starts or ends, a sound is ignored, music paused/resumed, volume lowered/restored, listening
  started/failed, permission missing, sleep, wake) each run one action — a Shortcut or a URL — with
  the event as input text. Drafts never fire, every hook has a cooldown, one run per hook at a time,
  a failing action is reported in Diagnostics rather than retried, and **Test** proves an action
  works on demand. No shell, scripting runtime or network client inside the app.
- A speech-shape filter in front of the coordinator, shipped as **Ignore notification sounds**
  (on by default).
  It reads the shape of a burst instead of its level: short blips, steady alert tones and
  single-decay chimes are logged in Diagnostics and ignored, while syllable-modulated speech still
  pauses or lowers Music. Speech that follows an alert inside the same window is still caught.
  The toggle in Settings restores the older any-sound behavior.
- **Choose the apps Oreja listens to.** Settings and onboarding show one list, grouped as AI
  assistants and voices (ChatGPT, Claude, Perplexity, Copilot, Siri), coding agents and terminals
  (Orca, Antigravity, VS Code, Terminal, iTerm2, Ghostty, Warp, Zed, Cursor, Windsurf), browsers
  (experimental), calls and messages (FaceTime, WhatsApp, Telegram, Slack, Zoom, Discord, Teams),
  video and podcasts, and any other app that is open. Several can be selected at once: a reply from
  any of them lowers or pauses Music. Music players cannot be selected as a source.
- Settings saved by 0.2.1 keep their single source; it becomes the first entry of the list.
- The Settings and onboarding picker shows which selected apps are running, and which are playing
  audio right now.

### Fixed

- **The AI listener did not come back after sleep.** Sleep stopped the microphone monitor but kept
  the app monitor, so after waking it was never recreated and the app stopped hearing the assistant.
  Sleep now stops both monitors and wake recreates them. 0.2.1 fixed the same problem for the
  microphone only.
- **A stale activity state could block later pauses.** Stopping the monitor cleared the activity
  tracker without telling the coordinator, so the next voice could start without pausing or
  lowering Music.

### Changed

- The audio-capture usage text says "the apps you select" instead of naming one app.

### Known limitations

- Reported working in a live test with ChatGPT desktop and a browser (ego lite) selected. The log
  records when Music was lowered and restored, but not which selected app caused each change.
- Not verified live: Claude desktop, Chrome, Safari, calls, and the coding agents other than Orca,
  Antigravity and VS Code. The bundle identifiers of apps that are not installed are not confirmed.
  A selected app that uses a different identifier still appears under "Other running apps".
- A terminal's own audio process carries speech only when the terminal renders it. A `say` command
  or voice script run inside a terminal is a separate process and is not captured.
- Safari's audio prefix also matches WebKit processes from other apps.
- Apple Music is the only music player. Spotify and the others are not supported yet.
- The build is ad-hoc signed and not notarized.

## [0.2.1] - 2026-11-02

One fix, plus the repository clean-up that preceded the public release.

### Fixed

- **Pause while I speak survived sleep again.** `AVAudioEngine` can stop delivering input while the
  Mac sleeps, and the app kept the dead monitor: after waking, the microphone level froze and the
  feature only returned after a restart. The monitor is now stopped on sleep and rebuilt on wake,
  so every wake starts a fresh tap. Coordinator decisions and the Apple Music path are unchanged.

### Changed

- The landing page's scroll runtime is `site/motion.js` with its stylesheet `site/motion.css`. It
  is the same runtime, under the site's own name, and it is documented in `site/README.md`.
- The repository no longer ships internal design-process notes or the two-agent notice board, so
  what remains is what a reader of the project needs. Their conclusions live in `DESIGN.md` and
  `docs/design-tokens.md`.

## [0.2.0] - 2026-11-02

The character release: the app, the icon and the website are one drawing now.

### Added

- **Vincent**, the pixel companion, in the menu bar panel, the Settings header and the first
  onboarding step. He blinks every few seconds, switches to his listening frames while the selected
  app is speaking, and a click plays his ouch frame with a short shake. Reduce Motion plays the
  frame without the shake. Clicking him changes no playback state and sends nothing.
- A new app icon and wordmark: Vincent's head, cropped from the same sprite sheet the companion
  draws from, generated by `tools/IconBuilder`. The menu bar mark, the window mark and the site's
  `mark.png` all come from that one crop, so they cannot drift apart.
- The Settings footer shows the version, and links to the repository and to this changelog.

### Changed

- Settings is rebuilt around the same groups as onboarding — behaviour, source, music, startup,
  then privacy and permissions — with native controls, brand spacing and one 500 pt column instead
  of form chrome.
- The menu bar panel is roomier: a larger mark, status text with the character beside it, and more
  space between the rows that carry a switch.
- The app and the website share one accent value for small text and controls, so the two surfaces
  cannot drift apart. Decorative coral stays decorative.
- The landing page and documentation were rebuilt: a scroll-driven night, a desk scene drawn in code
  rather than painted as an image, and a docs page that says which checks were run and which were
  not.

### Not changed

- The pause/resume coordinator, the audio path and the Apple Music adapter are the same code as
  0.1.0. Nothing here changes when your music stops.

## [0.1.0] - 2026-11-01

First public build: an ad-hoc signed DMG on the landing page and on the GitHub release.

### Added

- Menu bar app for macOS 14.2 and newer. No Dock icon, no account, no API key, no network code.
- Core Audio process taps targeted at the selected application, its helpers and its browsers,
  unmuted, so the monitored audio keeps playing normally while Oreja reads its level.
- Pause or lower-volume modes for Apple Music through Apple Events, with the original volume
  restored exactly in lower-volume mode.
- A deterministic playback coordinator that owns every pause: manual playback changes win, a track
  change releases ownership, and a pause journal restores playback after a crash only when the same
  track is still paused.
- Configurable quiet interval (300–3000 ms) and an optional conversation hold that keeps music
  paused through a whole exchange, including while the assistant is still working.
- Optional "Pause while I speak", which uses the microphone under its own permission and can only
  keep a pause alive, never create one.
- Six-step onboarding with a real connection test, Settings, and in-memory diagnostics with a copy
  action.
- Start at login through `SMAppService`.
- 54 automated tests across the coordinator, detector, settings, pause journal and AppleScript
  parsing.

### Known limitations

- A live ChatGPT Voice session has not been exercised. The ChatGPT audio path is verified against a
  controlled fixture, not against real replies. See [docs/test-evidence.md](docs/test-evidence.md).
- Ad-hoc signed and not notarized, so another Mac needs a one-time Gatekeeper approval.
- Browser sources are experimental and capture every tab in that browser.
- CPU, battery, Bluetooth and latency figures are unmeasured on real sessions.
- macOS only. iOS is researched in [docs/ios-strategy.md](docs/ios-strategy.md); no iOS code exists.

[Unreleased]: https://github.com/EnzoVezzaro/oreja/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/EnzoVezzaro/oreja/releases/tag/v0.5.0
[0.1.0]: https://github.com/EnzoVezzaro/oreja/releases/tag/v0.1.0
