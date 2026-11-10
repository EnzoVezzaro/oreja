# Handoff: multi-select audio sources and e2e checks

Date: 2026-11-09. Repo: `/Users/mac/Desktop/Github/oreja`. Branch: working tree on top of `e6e94ce`.
Read `AGENTS.md` first. Its rules still apply: the coordinator owns pause and resume, samples are
never stored, and nothing is reported as passed unless it was run.

## 1. Goal

The user asked for four things, in order:

1. Let Oreja listen to more than one AI source at a time, not just ChatGPT.
2. Offer more audio apps as selectable sources: browsers, calls and messages, coding agents, media,
   and any other running app. This covers Claude desktop, Codex-style agents and AI mascots or
   assistants, as long as they are running.
3. Fix the issues found in the review, and make the docs match the code.
4. Run end-to-end tests.

## 2. Scope decision

Taken after a review of the plan. Recorded in `docs/test-evidence.md` and in the PRODUCT file.

- **"All AI at once" means:** the user selects any set of running apps. One process tap covers
  them all. Oreja cannot identify which app is an AI.
- **"All output audio" was NOT built.** A global tap cannot tell which app made a sound. Using one
  as a trigger would pause music for videos, calls and alerts. It is only a research spike, and it
  needs an ADR and a new privacy string first.
- **Only Apple Music is controlled.** Other music players (Spotify, VLC, browser tabs) are still
  gated. They need per-provider ownership in the coordinator first.
- **Music players can never be a source.** `AISourceCatalog.isSelectable` excludes them and Oreja's
  own bundle.

## 3. What changed

Files modified or created (uncommitted; run `git status`):

| Area | File | Change |
|---|---|---|
| Core domain | `packages/OrejaCore/.../Domain/AISource.swift` | Rewritten. `KnownAudioApp` catalog with categories (`AudioSourceCategory`). `AISourceSelection.Kind` gains `.app`. `normalized` canonicalises ChatGPT builds and drops music players and duplicates. `AIAudioSourceDescriptor(selections:)` merges prefixes into one descriptor. |
| Settings | `packages/OrejaCore/.../Settings/AppSettings.swift` | `aiSource` becomes `aiSources: [AISourceSelection]`. Settings v1 key is kept. The legacy `aiSource` key is still read when `aiSources` is absent. |
| Ports | `packages/OrejaCore/.../Protocols/CoreProtocols.swift` | New `MediaAdministration` port (`isProviderRunning`, `launchProvider`, `requestAutomationPermission`). It is `Sendable` and `@MainActor`. |
| Apple Music | `packages/OrejaMedia/.../AppleMusicController.swift` | Conforms to `MediaAdministration`. Playback code unchanged. |
| Mock | `packages/OrejaMedia/.../MockMusicController.swift` | Conforms to `MediaAdministration`. Injectable in tests. |
| Discovery | `packages/OrejaAudio/.../RunningApplicationCatalog.swift` | Rewritten. `choices(including:)` returns installed known apps, running apps, apps actually producing output (joined from `AudioProcessCatalog`), and other running regular apps. |
| App model | `apps/macos/AppModel.swift` | Holds `any MediaPlaybackController & MediaAdministration`. `toggleSource` replaces `selectSource`. Monitoring starts only with a non-empty set. Connection check is generic. |
| UI | `apps/macos/AudioSourcePicker.swift` | New. Shared multi-select list used by onboarding and Settings. |
| UI | `apps/macos/SettingsView.swift`, `apps/macos/OnboardingView.swift` | Use the shared picker. Old fixed browser list removed. Music checks use the port. |
| Plist | `packaging/Info.plist` | Capture usage string now says "the apps you select". |
| Tests | `Tests/OrejaTestRunner/AudioSourceTests.swift` | New suite, 14 cases. |
| Tests | `Tests/OrejaTestRunner/EntryPoint.swift`, `MediaAndSettingsTests.swift` | Suite registered. Old single-source assertions updated. |
| Docs | `AGENTS.md`, `PRODUCT.md`, `README.md`, `docs/compatibility.md`, `docs/chatgpt-sources.md`, `docs/privacy.md`, `docs/permissions.md`, `docs/architecture.md`, `docs/apple-music.md`, `docs/test-evidence.md` | Counts set to 83. Non-goal for ducking and mic corrected. Compatibility shows what is verified. |

Known apps are in `AISourceCatalog.knownApps`. Those with confirmed bundle IDs on this Mac:
ChatGPT (`com.openai.codex`), Orca (`com.stablyai.orca`), Antigravity (`com.google.antigravity-ide`),
VS Code (`com.microsoft.VSCode`), Terminal, Slack, FaceTime, WhatsApp, Telegram, Chrome, Safari,
ego lite, Podcasts, TV.

Bundle IDs that are **not verified** (the apps are not installed here): Claude
(`com.anthropic.claudefordesktop`), Perplexity, Copilot, Cursor, Windsurf, Zed, Warp, Ghostty,
iTerm2, Edge, Arc, Brave, Firefox, Zoom, Discord, Teams, Siri. Such an app still appears under
"Other running apps" if it runs.

## 4. Verification done

| Check | Result | Command |
|---|---|---|
| Automated suite | **83 passed, 0 failed, 372 assertions** | `./scripts/test.sh` |
| App build (only check that compiles `apps/macos`) | OK | `./scripts/build.sh --probe --fixture --no-sign` |
| App launch | OK: 3 Oreja frameworks loaded, footprint about 14 MB | `open build/Oreja.app`; `vmmap`; `lsof` |
| Real speech, pid tap, gate off | 3 bursts detected | `oreja-probe --pid <say pid>` |
| Real speech, pid tap, gate on | 3 bursts pass | `oreja-probe --pid <pid> --speech-gate` |
| Steady tone, bundle tap, gate on | suppressed as "steady alert tone" | `OrejaFixture` via `open`, then `oreja-probe --bundle com.oreja.fixture --speech-gate` |
| Full app with fixture selected in Settings | monitor, ignore tone, retarget after exit | settings written, log read, settings restored |
| Real picker list on this Mac | matches expectations | temporary program against `build/lib` |

Evidence for each check is in `docs/test-evidence.md`, under "Multi-select audio sources" and
"End-to-end capture tests".

## 5. Not done, and why

- **Pause and resume of Apple Music during a reply.** Not run. Music was stopped with no track.
  `AGENTS.md` forbids starting playback without an explicit request. The user was asked to start a song.
- **Real ChatGPT Voice conversation under the app.** Not confirmed at handoff. The user was asked to
  start one. The log showed ChatGPT audio processes appearing at 20:57:08 to 20:57:25 UTC, but
  nothing about the outcome has been checked. See section 7.
- **Two or more selected apps at once, live.** Not run.
- **Live capture of any app other than ChatGPT, the fixture and `say`.**
- **Safari `com.apple.WebKit` prefix.** Still broad: it matches WebKit processes from other apps. It
  stays until a live Safari capture confirms which processes carry Safari audio. Do not remove it
  blind: that could silence Safari.
- **Harness speech from a terminal (`say` or a voice script).** `say` runs as its own process with
  no bundle identifier, so selecting Terminal does not capture it. Fixing this needs process-ancestry
  attribution or a global tap. Not implemented.
- **`apps/macos` has no automated tests.** `scripts/test.sh` compiles only the three packages and the
  test runner. UI changes are only build-checked.
- **`MediaPlaybackController.setVolume` / ducking** existed before this work and are unchanged.
- **Roadmap "39 automated tests"** (`docs/roadmap.md:25`) is historical and was left as is.
- **Apple Music and the `musicProvider` setting.** The setting is written by the UI and never read.
  It is harmless while Apple Music is the only provider.

## 6. Risks to keep in mind

- **Notifications from a selected app can count as speech.** The speech-shape filter reduces this
  but does not remove it. Browsers are whole-process taps and capture every tab.
- **`say` splitting.** Two sentences with about 0.75 s of silence between them produced two bursts.
  The coordinator's resume delay and conversation hold should keep music paused across them. This
  has not been measured through the coordinator.
- **ego lite produced no capturable audio** during ChatGPT Voice (`docs/test-evidence.md`). Do not
  assume browser sources work until a live capture shows activity.
- **Settings migration:** a settings write now stores `aiSources` only. An older build reading the
  file falls back to ChatGPT. That is acceptable, but a downgrade loses the selection.
- **Ad-hoc signing:** TCC grants may reset after a rebuild (`docs/permissions.md`). Re-check the
  Screen and System Audio Recording and Automation grants after rebuilding.

## 7. Current state at handoff

- **Oreja is running** (pid 14340, from `build/Oreja.app`), with the user's original settings.
  Automation is on. Microphone listening is on ("Listening for your voice as well" in the log), so
  the user's own voice can also trigger a pause. Keep this separate from ChatGPT results.
- **Settings:** the user's original settings were exported to `/tmp/oreja-defaults-backup.plist`
  and restored after the fixture test. Do not overwrite them without restoring the backup
  afterwards. If `/tmp` has been cleared, ask the user.
- **Apple Music:** stopped, no track loaded. The user was asked to play a song. Not confirmed.
- **Fixture processes:** none running at handoff. Test-only fixture: `build/OrejaFixture.app`,
  bundle `com.oreja.fixture`. It is never bundled with the app.
- **Oreja log:** `~/Library/Logs/Oreja/oreja.log`. It was truncated just before the last launch, so
  it contains only the current session.

## 8. How to reproduce

```bash
./scripts/test.sh                                   # 83 tests
./scripts/build.sh --probe --fixture --no-sign      # app, probe, fixture
./build/bin/oreja-probe --list                      # live audio processes

# Speech from a real process (start a long say first)
say "This is a test sentence with several words in it, so the burst lasts long enough." &
./build/bin/oreja-probe --pid $(pgrep -n -x say) --seconds 8 --speech-gate

# Steady tone through LaunchServices
open -n build/OrejaFixture.app --args --delay 2 --duration 4 --log /tmp/oreja-fixture.log
./build/bin/oreja-probe --bundle com.oreja.fixture --seconds 12 --speech-gate

# Music pause/resume (needs Apple Music playing a track, and the user's request)
./build/bin/oreja-integration --file <wav> --lead 3 --tone 2.5   # see scripts/build.sh --harness
```

## 9. Next steps, in priority order

1. **Finish the ChatGPT Voice check.** Read `oreja.log` for `ChatGPT` activity start and end, and for
   `Paused Apple Music` and `Resumed`. Note the track name from the log. Record in
   `docs/test-evidence.md` exactly what was observed, including any pause caused by the user's voice.
2. **Music pause and resume end to end.** Needs a playing track and the user's request. Use the
   integration harness and record the timings.
3. **Two selected apps at once.** For example ChatGPT and VS Code, or the fixture plus ChatGPT. Check
   that a reply from either pauses music and that the pause is held until both are quiet.
4. **Verify the uncertain bundle IDs** by installing or opening each app, then running
   `oreja-probe --list`. Correct `KnownAudioApp` if an identifier differs.
5. **Narrow the Safari WebKit prefix** after a live Safari capture.
6. **Automated tests for `apps/macos`.** Either add a test target or move the picker and migration
   logic into a package, as the review recommended.
7. **Harness speech from terminals:** research process-ancestry attribution. Write an ADR first.
8. **Other music providers** only after step 2 passes and `AGENTS.md` non-goals are amended. Needs
   per-provider ownership in the coordinator.

## 10. Rules for whoever picks this up

- Do not edit `packages/OrejaCore` decision logic without a test in `Tests/OrejaTestRunner`.
- Do not start, pause or reset Apple Music, and do not change its volume, without an explicit
  request from the user for that action.
- Do not record audio or store samples. Do not add network access.
- Report exactly what was executed and what was not. Record evidence in `docs/test-evidence.md`.
- Coordinate with other agents through `.agents/COORDINATION.md`.

## 11. Update 2026-11-10

- Sleep bug fixed: the app monitor was not stopped on sleep, so wake never restarted it. Sleep now
  calls `stopMonitoring`, and wake recreates the monitor.
- Stale activity state fixed: `stopMonitoring` now tells the coordinator the activity ended.
- A live session confirmed the browser source (ego lite) and ChatGPT desktop produced ducking and
  restore cycles. Per-app attribution is still not logged.
- Released as 0.3.0 (build 5). See `CHANGELOG.md` and `docs/test-evidence.md`.
- Still open: a real sleep/wake cycle has not been run after the fix; Safari prefix; terminal
  speech; bundle IDs of uninstalled apps; automated tests for `apps/macos`.
