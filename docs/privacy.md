# Privacy

Oreja de Van Gogh is local-first and has no server. This document describes exactly what the app
does with data; it is a product description, not legal advice.

## Summary

| Data | Collected? | Stored? | Transmitted? |
| --- | --- | --- | --- |
| Conversation audio | No | No | No |
| Transcripts or prompts | No | No | No |
| Audio level samples (dBFS) | Computed in memory | No, discarded immediately | No |
| Track name/artist for the paused song | Held in memory while paused | Journal stores the track identity in `UserDefaults` for crash recovery | No |
| Settings | Yes | `UserDefaults` on this Mac | No |
| Diagnostic events | Yes, local state transitions | In-memory ring buffer, max 300 events | No |
| Account, email, identifiers | No | No | No |
| Analytics, crash reporting | No SDK | No | No |
| Network requests | None | — | — |

## Audio handling

1. For primary apps, Core Audio copies their **output** into a private aggregate device.
2. An IOProc on the real-time thread writes samples into a preallocated ring buffer. It never
   allocates, blocks, or writes files.
3. Every 50 ms, a utility task computes one RMS/dBFS value and overwrites the buffer.
4. The detector keeps only a boolean activity state and timing.
5. Raw samples are never persisted, never inspected for content, and never sent anywhere. No speech
   recognition, transcription, or speaker identification is performed.

Primary apps keep playing normally: their analysis tap is unmuted. Release 0.4.0 includes an
experimental Browser playback target using Apple Events and page scripting for standard HTML media
in its listed adapters. Page scripts control media elements in open tabs; they do not inspect page
text. The maker reported successful real playback testing, but the exact browser/site/settings were
not recorded. Music is not part of the analysis tap and remains controlled through its provider
adapter.

## Permissions and purpose strings

- **System audio recording** — to measure the selected app's output level.
- **Automation (Music and experimental Browser target)** — to control Music, and to run Apple
  Events/page scripts against selected browser adapters.
- No microphone, screen content, accessibility, full disk, contacts, or location access.

See `permissions.md`.

## Local storage

`UserDefaults`, domain `app.oreja.van-gogh` (standard defaults for the app):

- `com.oreja.settings.v1` — primary apps (`aiSources`), secondary mute targets (`targetAudioApps`; older builds stored `aiSource`, still read), provider, automation on/off, resume delay, launch at
  login, onboarding completion, verbose diagnostics.
- `com.oreja.pause-journal.v1` — only while Oreja owns a pause: provider, track identity, pause
  time. Deleted as soon as playback is restored or ownership is released.

The diagnostic log is memory only and is lost when the app quits. No file logs, no crash dumps
added by Oreja, no database.

## Network

The app links no networking framework and performs no requests. It works offline, without an
OpenAI API key, without an account, and without analytics. Future features (for example an optional
Realtime API voice mode on iOS) would be separate, opt-in, clearly priced integrations — not part of
the macOS core.

## Third parties

- OpenAI: none. Oreja does not communicate with ChatGPT beyond observing its local audio output.
- Apple: the app uses macOS audio and automation APIs; no data is sent to Apple by Oreja.
- No advertising, tracking, or data brokers.

## User control

- Turn automation off at any time; an owned pause is restored first.
- Revoke either permission in System Settings; the app stops controlling playback.
- Delete the app and its preferences to remove all local state:
  `defaults delete app.oreja.van-gogh`
- The pause journal exists only for crash safety and is cleared after use.

## Children and sensitive data

Oreja is a utility, not a data service. It does not knowingly collect any personal data, and it
cannot access conversation content by design.

## Changes

Any future feature that records, uploads, or analyzes content would require an explicit design
change, a new consent screen, and an update to this document. The core promise is that the default
product never records a conversation.

## Contact

The distributing party is responsible for publishing a contact address. No contact details are
included in this repository.
