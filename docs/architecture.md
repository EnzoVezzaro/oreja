# Architecture

## Design goal

One decision, made in one place: *should the user's music pause or resume right now?* Everything
else is an adapter. That is what makes the behavior testable without ChatGPT, Music, or a Mac audio
device, and what will let the same engine run on iPhone later.

Oreja is a companion, not a proxy. It does not touch ChatGPT's audio route, account, session, or
network traffic. It observes the selected application's audio output and controls a separate music
application.

## Modules

| Module | Contents | Allowed imports |
| --- | --- | --- |
| `OrejaCore` | Domain (`AISource`, media models, coordinator state), ports, `PlaybackCoordinator`, settings, pause journal, diagnostics | Foundation |
| `OrejaAudio` | Core Audio process catalog, process tap lifecycle, `LevelSampler`, `AudioActivityDetector` | CoreAudio, Foundation, `OrejaCore` |
| `OrejaMedia` | `AppleMusicController` + AppleScript runner, mock controller | AppKit (`NSAppleScript`), Foundation, `OrejaCore` |
| `apps/macos` | SwiftUI menu bar panel, onboarding, settings, diagnostics, `AppModel` wiring, launch-at-login | SwiftUI, AppKit, all packages |
| `tools/AudioProbe` | CLI capture diagnostic (`--list`, `--bundle`, `--pid`) | `OrejaAudio`, Foundation |

`OrejaCore` has no platform imports. The SwiftUI layer never makes a pause/resume decision; it
renders `CoordinatorState` and forwards user intent.

## Ports

Defined in `packages/OrejaCore/Sources/OrejaCore/Protocols/CoreProtocols.swift`:

- `AIAudioMonitoring` — async stream of monitor lifecycle and activity events.
- `AIAudioMonitorFactory` — creates the platform monitor for a source descriptor.
- `MediaPlaybackController` — `currentPlayback()`, `pause()`, `resume()`, `provider`, `capabilities`.
- `SettingsStoring`, `PauseJournal`, `DiagnosticsSink`.
- `SilenceScheduling` — injectable timer so tests control time.

Capabilities are data (`MediaCapabilities`), not assumptions: a provider declares whether it can
pause, resume, report track identity, or support volume changes. Unsupported operations return
typed `MediaControlError` values.

## Data flow

```
                    ┌──────────────────────── OrejaAudio ───────────────────────┐
ChatGPT processes → │ AudioProcessCatalog → CATapDescription → aggregate device │
                    │   → AudioDevice IOProc → LevelSampler (try-lock, bounded) │
                    │   → 50 ms analysis → AudioActivityDetector (hysteresis)   │
                    └──────────────────────────┬────────────────────────────────┘
                                               │ AudioActivityEvent
                                      ┌────────▼─────────┐
                                      │  AppModel        │  (MainActor)
                                      │  adapter loop    │
                                      └────────┬─────────┘
                              activity / media │ ▲ Command
                                      ┌────────▼─┴───────┐
                                      │ PlaybackCoordinator │  deterministic, @MainActor
                                      └────────┬─────────┘
                                               │ pause() / resume()
                                      ┌────────▼─────────┐
                                      │ AppleMusicController │ → NSAppleScript → Music
                                      └──────────────────┘
```

Media state is observed once per second via `currentPlayback()`; the coordinator uses those
observations to detect manual overrides, track changes, and provider exit.

## Coordinator contract

Inputs (all explicit events):

- `setAutomationEnabled`, `updatePolicy`
- `monitoringBecameAvailable(description:)`, `monitoringFailed(_:)`, `sourceInvalidated(reason:)`
- `audioActivityStarted(levelDB:)`, `audioActivityEnded()`
- `observe(media:)`
- `complete(_:outcome:)` for issued commands
- `systemWillSleep()`, `systemDidWake()`, `retryAfterError()`
- `commandForTermination()`, `acknowledgeTermination()`

Outputs:

- `state: CoordinatorState` and a diagnostics log.
- `onCommand(Command)` — a `pause` or `resume` with an ID and the track it expects.
- `onStateChanged()` for the UI.

A command is not assumed to have succeeded. The adapter executes it and calls
`complete(id, outcome:)` with the state it observed. On Apple Music that observation comes from the
same Apple Event as the command (`pauseReporting()` / `resumeReporting()`: pause, wait inside Music
for the new state, return the full snapshot), which removes a whole round trip from the pause path.
Adapters that only implement `pause()`/`resume()` inherit a default that reads the state after the
command. `noOp` outcomes (for example, the track changed before the command ran) release the intent
without counting as a failure.

### States

`disabled`, `searchingForSource`, `monitoring`, `musicPlaying`, `aiActive`,
`musicPausedByOreja`, `waitingForSilence`, `restoringPlayback`, `suspended`,
`permissionRequired`, `error`.

The enum is intentionally coarse: one state is displayed everywhere. Finer flags live beside it
(`aiIsActive`, `ownership`, `pendingCommand`, `sourceIsValid`, `userOverrodeDuringActivity`).

### Ownership and safety rules

- Oreja pauses only if Music is **playing** and no command is pending.
- A pause creates `PauseOwnership` (track, provider, time) and a journal record.
- Resume requires all of: quiet interval elapsed, Oreja owns the pause, the user has not overridden
  playback, the source is still valid, the provider is available, and no command is in flight.
- A manual pause observed while Oreja is not active clears any intent to pause. A manual resume
  during AI activity is honored: ownership is dropped and the next speech onset may pause again.
- A track change while paused releases ownership instead of resuming a different song.
- Source loss or permission loss ends activity, releases ownership, and, if configured, restores
  the pause once. Monitoring is never restarted in a tight loop; retries are bounded and delayed.
- `failureLimit` consecutive command failures stop automation and surface an error rather than
  retrying forever.
- Quit restores an owned pause synchronously enough to use `NSApplication.terminateLater`.
- On launch, a stale journal is restored only when it is younger than 12 hours and points at the
  same track that is still paused. Otherwise it is discarded.

### Timing defaults

| Setting | Default | Range |
| --- | --- | --- |
| Activity onset debounce | 60 ms | policy |
| AI silence window (detector end) | 250 ms | policy |
| Resume delay (coordinator quiet interval) | 800 ms | 300–3000 ms |
| Conversation hold (silence that ends a conversation) | 12 s | 2–60 s, or off |
| Level analysis period | 30 ms | implementation |
| Data watchdog while active | 1.5 s | implementation |
| Media observation period | 1 s | implementation |

The 250 ms detector window protects against syllable gaps; the resume delay is the user-facing
"wait before the music comes back" control.

A spoken conversation is mostly silence: the assistant stops talking, works on the answer, then you
answer, and only then does it speak again. Resuming after 800 ms would therefore drop music into the
middle of the exchange. `PlaybackPolicy.conversationHold` replaces that wait with a longer one
(`resumeWait = max(quietInterval, conversationHold)`), so every turn restarts the same timer and the
music returns only when the whole conversation has been quiet. It is one number, not a second state
machine: the pause is still owned by the coordinator and the manual-override, source-loss and
provider rules are unchanged.

`pauseWhileISpeak` feeds the microphone into the same activity stream, but only while music is not
playing. If the microphone could start a pause, speaker output would close a loop: music on →
microphone hears the music → pause → silence → resume → music on. The assistant's output starts the
pause; the microphone merely keeps it alive.

## Real-time audio safety

The IOProc block runs on Core Audio's real-time thread. It accumulates sum-of-squares in
`LevelSampler` using `os_unfair_lock_trylock`: if the analysis task holds the lock, the audio frame
is dropped rather than waited on. It does not allocate, block, log, touch the filesystem, or call
Swift concurrency. A detached utility task drains the accumulator every 50 ms, computes RMS/dBFS,
and feeds the detector. Audio samples are never retained beyond the callback and never persisted.

The tap is private and unmuted (`CATapMuteBehavior` raw value 0), so the target app keeps its
normal output. Only the selected application's processes are tapped; Music is never part of the
tap. Taps, the aggregate device, and the IOProc are destroyed on stop, failure, and deinit.

## Process set while a conversation runs

A voice conversation does not keep a fixed set of audio processes. ChatGPT's desktop app and every
Chromium browser create and destroy renderer/utility audio processes per session, and they flip
`kAudioProcessPropertyIsRunningOutput` on and off with each spoken turn. The monitor therefore:

- taps **every** process that matches the selected source, including ones that are quiet right now.
  Preferring only the processes that report output would rebuild the tap at the instant a sentence
  starts and lose its first syllables;
- listens for `kAudioHardwarePropertyProcessObjectList` changes and rebuilds the tap when the app
  spawns or drops a process, with a one-second poll as a fallback;
- asks the aggregate device for a small IO buffer (1024 frames, about 23 ms), because the default
  buffer alone can delay detection by several hundred milliseconds;
- keeps the monitor alive when the app currently has no audio process at all, instead of failing
  and retrying: Chrome only spawns its audio service on the first sound, so a failing monitor would
  miss the first sentence while it waited for the next retry. The monitor stays up with no tap
  (`"… (waiting for its audio process)"`), and the process-list listener gives it the tap the
  moment the process appears. When the last process disappears the tap is torn down and the monitor
  returns to that waiting state.

Monitoring is therefore driven entirely by the Core Audio process list. There is no timer that
rebuilds a tap for an app that is closed, and no separate "is the app running" poll to disagree with
what Core Audio reports.

## Failure handling

| Failure | Behavior |
| --- | --- |
| Audio capture permission missing | `permissionRequired`, no playback automation, direct links to System Settings |
| Source app quits | its audio processes vanish; the tap is torn down and the monitor waits for the app to come back |
| Source app has no audio process yet | monitor stays up without a tap; the process-list listener attaches it when one appears |
| Music quits | provider unavailable; ownership released; no retry storm |
| Music automation denied | typed error, actionable message, no silent success |
| Output device change | tap stops delivering; watchdog ends activity; monitor is re-established |
| Sleep/wake | state `suspended`; on wake the coordinator reconciles with observed playback |
| Oreja quits while holding a pause | resume once before termination |
| Oreja crashes while holding a pause | journal restores only the same paused track on next launch |

## Packaging

`scripts/build.sh` compiles four Swift modules with `swiftc` (this machine's SwiftPM manifest
library is broken), generates the icon, assembles `build/Oreja.app`, and ad-hoc signs it with the
audio/automation entitlements (hardened runtime only with a real signing identity, because ad-hoc
signatures have no team identity for library validation). `Package.swift` describes the same targets for
Xcode users. `LSUIElement` keeps the app out of the Dock. See `docs/distribution.md`.

## Testing strategy

- The coordinator is tested with a fake scheduler and fake media controller: no sleeps, no real
  time, every race expressed as an explicit sequence of events.
- The detector is tested with synthetic dBFS sequences.
- AppleScript generation/parsing and error mapping are tested without launching Music.
- Core Audio is verified separately with `oreja-probe` against a real process, because a mock
  cannot prove a process tap works.
- A real ChatGPT Voice + Apple Music run remains the outstanding acceptance test
  (`docs/test-evidence.md`).

## Extending to other platforms

`PlaybackCoordinator`, domain models, settings, and policy are portable Swift and can be shared with
an iOS target. A platform supplies `AIAudioMonitoring` and `MediaPlaybackController`
implementations. For non-Swift platforms, the transition contract is the event/command list above
plus the test fixtures in `Tests/OrejaTestRunner/CoordinatorTests.swift`; those sequences are the
specification, not the implementation detail.
