# Compatibility

This matrix separates what was observed on the development machine from what is expected. Do not
read "expected" as verified; see `test-evidence.md`.

## macOS

| macOS | Status | Notes |
| --- | --- | --- |
| 14.2 – 14.x | Expected | Core Audio process taps exist. Not tested here. |
| 15.x | Expected | Not tested here. |
| 26.6.2 (25G83), Apple M2 | **Tested** | Build, launch, process discovery, and process-tap capture verified. |
| Intel Macs | Expected | Source builds for `arm64` by default; set `ARCH=x86_64` or build on the target (the script derives the architecture from `uname -m`). Not tested. |
| macOS < 14.2 | Unsupported | The app reports that process taps need 14.2+. |

## AI source

| Source | Status | Bundle identifiers | Notes |
| --- | --- | --- | --- |
| ChatGPT desktop (2026 build, Voice / Read aloud) | **Verified live** (desktop Read aloud: two pauses and resumes; see `test-evidence.md`) | `com.openai.codex` | Matched by the `com.openai.` prefix. The full Voice conversation was not separately measured. |
| ChatGPT desktop (older builds) | Expected | `com.openai.chat`, `com.openai.chatgpt` | Canonicalised to the one ChatGPT selection. |
| Helper processes | Supported by design | per app | All matching processes are tapped, including ones that are quiet, so the first syllables are not lost. |
| Claude desktop | **Not verified** | `com.anthropic.claudefordesktop` (from the vendor's identifier; not installed on the test Mac) | Appears under AI assistants if installed with that identifier; otherwise under Other running apps. |
| Coding agents and terminals (Antigravity, Orca, VS Code, Terminal, iTerm2, Ghostty, Warp, Zed, Cursor, Windsurf) | Listed; live capture of agent speech **not verified** | see `KnownAudioApp` | Only Antigravity, Orca, VS Code and Terminal are installed on the test Mac, and none was tested with speech. A terminal app only captures audio its own processes render. A `say` or script run from a terminal is a separate process with no bundle identifier, so it is not captured. |
| Calls and messages (FaceTime, WhatsApp, Telegram, Slack, Zoom, Discord, Teams) | Listed; **not verified** | see `KnownAudioApp` | Only Slack, FaceTime, WhatsApp and Telegram are installed on the test Mac; none was tested in a call. |
| Browsers as interruption sources (Chrome, Safari, Edge, Arc, Brave, Firefox, ego lite) | Experimental | see `KnownAudioApp` | Process-level monitoring can include audio from every tab; the browser source has not been verified live as a group. In 0.5.0 testing ego lite audio was captured through its helper process (YouTube detected at −15 dBFS); a ChatGPT Web reply was not measured (`test-evidence.md`). Safari's `com.apple.WebKit` prefix can also match WebKit processes of other apps. This row describes listening only, not controlling browser playback. |
| Siri | Experimental, not verified | `com.apple.SiriNCService`, `com.apple.assistant` | Listed as a system service; its audio process is not confirmed. |
| Any other running app | Supported by design, **not verified per app** | the app's bundle identifier | Shown under Other running apps. Notifications from a selected app can count as speech; the speech-shape filter reduces this. |
| ChatGPT Classic macOS voice | Unsupported | — | Retired by OpenAI in January 2026. |
| Music players (Apple Music, Spotify, VLC) | Never selectable as an AI source | — | The music is what Oreja pauses; selecting it would trigger its own pause. |
| Oreja-owned Realtime API session | Not implemented on macOS | — | Planned for the iOS fallback, not required for macOS. |

## Music provider

| Provider | Status | Notes |
| --- | --- | --- |
| Apple Music (Music.app), local library | Pause/lower implemented; maker-confirmed live in 0.5.0 | Apple Events. Requires Automation consent; never launched by Oreja. |
| Apple Music streaming/radio | Expected, unverified | Same play/pause commands; buffer/queue behavior untested. |
| Spotify, VLC, other players | Lowered / silenced (0.5.0) | Selected under Lower these apps. Process tap mutes the app and replays it at the duck level; pause mode silences it. No native pause. Not tested here: neither app is installed on the test Mac. |
| Browser media (any tab, any player) | Lowered / silenced (0.5.0) | Choose the browser under Lower these apps (Chrome, Edge, Brave, Arc, Firefox, ego lite). Same process-tap mechanism; no browser setting, no page scripting. Safari is not supported (shared WebKit audio process). A browser used for ChatGPT Web cannot also be lowered. Live: YouTube in ego lite lowered to 11% on a real voice onset and restored (`test-evidence.md`). |
| Internet Explorer | Unsupported | Internet Explorer has no current macOS release and cannot be a target on this macOS-only app. |
| YouTube Music and other players | Lowered via the browser or app (0.5.0) | Choose the browser or the app under Lower these apps. No native pause. |

## Audio devices

Only the default output device of the test Mac was used, and only for the capture probe (not for a
real ChatGPT/Music conversation).

| Device / scenario | Status |
| --- | --- |
| Built-in speakers | Process-tap capture verified with a controlled process; full conversation not tested |
| Wired headphones | Not tested |
| Bluetooth headphones / AirPods | Not tested |
| Device switch during playback | Not tested; the watchdog ends activity if the tap stops delivering, and monitoring is re-established |
| Multi-output / aggregate devices | Not tested |
| External USB interface | Not tested |

## Interaction matrix

| Scenario | Behavior |
| --- | --- |
| ChatGPT in foreground or background | Monitoring is process-scoped, so foreground/background should not matter. macOS may throttle background audio apps but ChatGPT keeps playing; unverified. |
| Music paused by the user | Oreja leaves it paused |
| User resumes Music while ChatGPT speaks | Honored; Oreja drops ownership and may pause again at the next response |
| User changes track while paused | Ownership released; the new track is not resumed by Oreja |
| ChatGPT quits | Activity ends; owned pause restored once; monitoring retries slowly while automation is on |
| Music quits | Provider unavailable; no retry storm |
| Oreja quits while holding a pause | Music is resumed before exit |
| Oreja crashes while holding a pause | Journal restores the same paused track on next launch |
| Sleep/wake | Suspended state; on wake, state is reconciled from real playback |
| Audio capture permission revoked | Monitoring stops, error shown, no automation |
| Two quick ChatGPT responses | Hysteresis plus debounce; no pause/resume oscillation |
| ChatGPT notification sound | Ignored: the speech-shape filter rejects brief, steady and single-decay bursts (on by default) |
| Chime followed immediately by a reply | The reply still pauses; a suppressed window stays open |
| Ringtone or beat-driven alert from the source | Treated as activity: modulated like speech. Turn off “Ignore notification sounds”, or use a dedicated source |

## Known limitations

- Detection is speech-*shaped* output activity, not speech recognition: a long modulated non-speech sound still counts.
- Browser monitoring as an interruption source is process-wide; audio from any tab may count. This
  is separate from the Browser playback target.
- Browsers and other players are lowered or silenced through a muted process tap and replayed at
  the duck level; they cannot be paused. Safari is excluded. ChatGPT Web and music in the same
  browser cannot be separated: use a different browser for music.
- Ad-hoc signing means TCC grants may reset when the app is rebuilt.
- No notarization: another Mac needs Gatekeeper approval.
- The app is a menu bar utility; there is no Dock icon or main window by design.
