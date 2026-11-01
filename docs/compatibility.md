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
| ChatGPT desktop (2026 build, Voice in Work/Codex) | Installed and discovered; live voice unverified | `com.openai.codex` | `/Applications/ChatGPT.app` on the test Mac registers as `com.openai.codex`. Voice requires sign-in and an interactive session, so no live audio test was possible. |
| ChatGPT desktop (older builds) | Expected | `com.openai.chat`, `com.openai.chatgpt` | Included in the catalog. |
| Helper processes | Supported by design | `com.openai.*` | All matching processes that are running output are tapped; if none report output, all matching processes are tapped. |
| ChatGPT on chatgpt.com in Safari or Chrome | Experimental | `com.apple.Safari`, `com.google.Chrome` | Selectable in onboarding. A browser tap hears every tab in that browser, plus browser sound effects. Edge, Arc, Brave, and Firefox identifiers are recognized by the catalog but are not offered in the picker yet. |
| ChatGPT Classic macOS voice | Unsupported | — | Retired by OpenAI in January 2026. |
| Claude / Gemini voice apps | Not implemented | — | Ports exist; no adapter yet. |
| Oreja-owned Realtime API session | Not implemented on macOS | — | Planned for the iOS fallback, not required for macOS. |

## Music provider

| Provider | Status | Notes |
| --- | --- | --- |
| Apple Music (Music.app), local library | Control implemented, live unverified | Apple Events. Requires Automation consent; never launched by Oreja. |
| Apple Music streaming/radio | Expected, unverified | Same play/pause commands; buffer/queue behavior untested. |
| Spotify, YouTube Music, VLC | Not implemented | Capability-based adapters planned. |

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
| ChatGPT notification sound | Treated as activity (documented limitation) |

## Known limitations

- Detection is output activity, not verified speech.
- Browser monitoring is whole-browser.
- Ad-hoc signing means TCC grants may reset when the app is rebuilt.
- No notarization: another Mac needs Gatekeeper approval.
- The app is a menu bar utility; there is no Dock icon or main window by design.
