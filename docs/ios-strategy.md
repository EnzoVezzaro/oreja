# iOS strategy

Status: **research only.** No iPhone app exists in this repository. The macOS MVP is the priority,
and the iOS architecture below must be validated on a device before it is promised to anyone.

## The constraint

iOS does not provide a public equivalent of macOS Core Audio process taps. A third-party app
cannot silently observe another app's audio output. The relevant facts:

| Capability | iOS public API | Consequence |
| --- | --- | --- |
| Capture another app's audio while it runs in the foreground/background | None | Strategy A cannot be automatic. |
| ReplayKit | Captures screen/audio only during an explicit user-started broadcast or recording, with system UI; not a background monitor | Not suitable for an always-on companion. |
| `AVAudioSession` interruptions | Notify an app about its **own** session being interrupted | Do not expose ChatGPT's speech start/stop. |
| Background audio | Allowed only while the app itself is producing audio and declares the audio background mode | Cannot be used to passively listen to another app. |
| MusicKit / `SystemMusicPlayer` | Controls Apple Music playback, requires subscription and entitlement | Can pause/resume music, but only from an app that is active or has a valid background reason. |
| `UIBackgroundModes` / background tasks | Time-limited, no persistent cross-app monitoring | No always-on watcher. |
| Accessibility / private APIs | Not available to App Store apps | Rejected. |

An app cannot read the microphone to determine when ChatGPT is speaking: it would hear the room and
the speaker output, which is exactly the failure mode the macOS design avoids.

## Strategy A — companion to the external ChatGPT app

**Goal:** ChatGPT runs on its own; Oreja detects when it is speaking and controls Music.

**Verdict: not viable as an automatic feature with public APIs.** There is no supported signal for
another app's speech state on iOS. Approaches considered and rejected:

- Silent audio session + interruption notifications: interruptions only report that Oreja's own
  session was interrupted; they do not identify ChatGPT's speech boundaries.
- ReplayKit broadcast extension: requires the user to start a broadcast and shows system UI; not a
  silent companion, and the extension cannot control the foreground ChatGPT app.
- Screen-time/accessibility or keyboard hooks: no public API, App Store violation.
- Shortcuts/personal automations: cannot watch another app's audio continuously.
- Push or server-side detection: requires recording or proxying the conversation, which violates the
  privacy model and is not possible for the consumer ChatGPT app.

**What Oreja could honestly do:** a limited companion (Strategy C) with manual pause/resume, or an
in-app experience (Strategy B). Shipping Strategy A labelled "automatic" would be misleading.

## Strategy B — in-app conversational voice using the Realtime API

**Goal:** Oreja offers its own voice conversation, and music coordination is derived from the audio
Oreja itself plays. This is not the ChatGPT consumer app, session, subscription, or history.

Architecture:

1. **Session:** OpenAI Realtime API over WebSocket/WebRTC, with a user-supplied API key stored in the
   Keychain. No shared secret in the binary; no proxy server required for a local-first design, but
   the key is extractable on a jailbroken device, so document the trade-off or offer a user-owned
   backend later.
2. **Playback observation:** tap Oreja's own outgoing audio buffers (`AVAudioEngine` player node or
   the WebRTC audio unit). Activity starts when output buffers contain non-silent samples and ends
   after a configurable silence window — the same signal contract as macOS, not a server "done"
   event, because generation completion and audible playback are different moments.
3. **Music:** MusicKit `SystemMusicPlayer`/`ApplicationMusicPlayer` pause/resume, with the user's
   Apple Music subscription. Preserve track and position; respect manual overrides.
4. **Audio session:** `.playback` (or `.playAndRecord` if user speech is captured), mix with others
   where appropriate, handle interruptions and route changes; restore music only when the session is
   active and Oreja owns the pause.
5. **Shared core:** reuse `OrejaCore` (coordinator, policy, ownership, settings, journal) unchanged.
   New iOS adapters implement `AIAudioMonitoring` (own playback) and `MediaPlaybackController`
   (MusicKit).
6. **UX:** a normal in-app chat/voice interface, a clear "this uses your OpenAI API key and may incur
   charges" disclosure, and a visible difference from the ChatGPT app. Never claim account or
   subscription parity.

Cost and product implications: API usage is billed to the user's OpenAI account; there is no
consumer subscription passthrough. This is a different product surface, not a drop-in companion.

## Strategy C — limited companion controls

If cross-app automation is impossible, ship only what iOS permits and label it plainly:

- A Control Center / Lock Screen / Shortcuts action to pause and resume Apple Music around a voice
  session the user starts manually ("I'm about to talk to ChatGPT").
- Optional MusicKit playback controls and a Live Activity showing which phase the user is in.
- A one-tap "resume music" after the conversation.
- No claim of automatic detection, no background listening, no microphone surveillance.

This is honest and useful, but it is a manual tool, not the macOS experience.

## Recommendation

1. Do **not** ship Strategy A as automatic.
2. Prototype **B** if the product can support its own voice experience, including API cost and an
   explicit identity separate from ChatGPT. It is the only path to the intended automatic behavior
   on iPhone.
3. Otherwise ship **C** and describe it as manual.
4. Share `OrejaCore`; keep platform adapters thin.

## Validation plan (before any iOS claim)

- Confirm current MusicKit entitlements and subscription requirements on a physical iPhone.
- Test `SystemMusicPlayer` pause/resume from foreground, background audio mode, Lock Screen, and
  after an interruption.
- Test route changes: speaker, wired, Bluetooth, AirPods, AirPlay.
- Test the Realtime API playback observation under network jitter and interruptions.
- Verify background execution limits: iOS may suspend the app when it is not producing audio.
- Battery and thermal measurements over a 30-minute conversation.
- App Store review check for background audio justification and API-key handling.
- Privacy review: no conversation recording, explicit consent for microphone if used.

Until those pass, the iPhone product is a plan, not a deliverable.
