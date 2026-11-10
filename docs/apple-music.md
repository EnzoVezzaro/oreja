# Apple Music connection guide

Oreja controls Music through Apple Events (`NSAppleScript`). This is the documented automation path
for the macOS Music application; no private API is used.

## What the scripts do

| Script | Action | Guarantees |
| --- | --- | --- |
| `playbackState` | Reads `player state`, track persistent ID/name/artist, `sound volume` | Field-separated output parsed by `AppleMusicStateParser`; unknown states become `unavailable` |
| `pause` | `tell application "Music" to pause` | Track, queue and position preserved |
| `resume` | `tell application "Music" to play` | Resumes the same track from where it stopped |
| `setVolume` | Used for volume ducking while the AI speaks | Clamped 0–100; the adapter reports `canSetVolume = true`; restored when the conversation is quiet |

Every script is wrapped in `if application "Music" is running then`. Oreja never launches Music on
its own; only the onboarding "Open Music" button does, at the user's request.

## Why `pause` and not `stop`

`stop` clears the player position and, in practice, the user's listening context. `pause` keeps the
track loaded and the position intact, which is what makes a resume feel seamless.

## Ownership: how Oreja knows the pause is its own

- When a pause succeeds, the coordinator records `PauseOwnership(track:persistentID, provider,
  acquiredAt)` and writes it to the pause journal.
- Before resuming, it re-reads the player state and requires the loaded track's persistent ID to
  match. A different track means the user moved on: Oreja releases ownership and does not resume.
- If the user resumes Music themselves, the next observation sees `playing`, releases ownership and
  Oreja stays out of the way for the rest of that response.

## Error mapping

| AppleScript error | Meaning | Oreja behaviour |
| --- | --- | --- |
| `-1743` | Automation not permitted | `permissionDenied` → `permissionRequired` state |
| `-600` | Music not running | `notRunning` → provider treated as unavailable |
| `-1728` | Item not found | `commandFailed` with the script's message |
| other | Unknown | `commandFailed("Music automation failed (code): message")` |

## Connecting it, step by step

1. Open Music and start any song.
2. First time only: launch Oreja and use **Run connection test** (menu bar) or the onboarding check.
   macOS shows "Oreja wants to control Music" — choose OK.
3. If you dismissed it, enable Oreja under System Settings › Privacy & Security › Automation.
4. Verify: the menu bar shows "Apple Music is playing" and, when ChatGPT speaks, "Music paused by
   Oreja" followed by a resume after the quiet interval.

## Not covered in this release

- Volume ducking, queue inspection, playlist control, lyrics, AirPlay routing.
- Spotify or other providers: `MediaPlaybackController` is provider-neutral, but no adapter exists
  yet, and each provider declares its own capabilities (`MediaCapabilities`).
- Library access. Oreja reads only the currently loaded track.
