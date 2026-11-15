# Playback targets and interruption sources

Date: 2026-11-15  
Branch: `codex/dual-audio-sources`  
Status: initial Browser target shipped experimentally in 0.4.0 by explicit user direction. The
reliability requirements below remain follow-up work before calling browser control broadly stable.

## Goal

Make Settings legible and reliable, and keep two separate concepts:

- **Interruption sources** are apps whose output Oreja detects as speech (for example, ChatGPT).
- **Playback targets** are media Oreja controls while an interruption is active (Apple Music, Spotify, or browser media where an adapter can guarantee ownership).

The selected interruption mode is pause or lower. User speech uses the same playback interruption when “Pause while I speak” is enabled. Existing settings and features must survive migration.

## Verified capability boundary

The current Apple Music adapter remains supported. Spotify is not implemented in the current branch. The current browser Apple Events script can reach some standard HTML media elements, but polling those elements cannot guarantee that Oreja will distinguish a user's manual pause/resume from its own command, and it misses protected/non-HTML media. It therefore cannot be presented as a reliable playback adapter or used to claim session ownership.

Browser playback control must use a browser extension that observes media state transitions and communicates with a local native helper. The extension pauses only media that was playing at the interruption edge, restores only sessions it paused, and relinquishes ownership after a user pause. Extensions can cover Chromium-family browsers and Firefox with browser-specific native-messaging registration. Safari requires Safari Web Extension packaging/installation. Internet Explorer is not a macOS browser target. Unsupported browsers must be identified in Settings; no process mute, app termination, or global media keys may stand in for session control.

Until the extension/native-helper handshake is implemented and verified, Browser and Spotify must be visibly marked unavailable/experimental and must not run the existing best-effort script as if it met these guarantees. The “All supported browsers” and “Active browser only” scope belongs to the Browser target settings. “Active” means the frontmost supported browser at the start of the interruption.

Multiple playback targets are a later extension of the model. Keep target identity and adapter capability separate from interruption source selections so adding a set of targets does not require another settings redesign.

## Settings redesign

- Use a compact fixed header and a persistent section sidebar; keep one scrollable content pane.
- Organize settings by user task: interruption sources, playback targets and response, detection, automation, privacy.
- Make app rows compact and searchable, with category and installed/running/support state where available.
- Show browser support and permission state in the Browser target row and details; do not imply universal support.
- Keep pause/lower behavior, duck level, restoration timing, microphone option, sensitivity, notification filtering, hooks, launch behavior, diagnostics, permissions, and all other existing features.
- Preserve keyboard navigation, VoiceOver names, dark mode, and resize behavior. Avoid duplicate labels and repeated descriptions.

## Implementation sequence

1. Keep the work on this feature branch and record capability findings here before code changes.
2. Introduce separate playback-target identity and browser scope in persisted settings, including backward-compatible decoding.
3. Remove browser use of process mute and best-effort Apple Events polling from the guaranteed playback path. Retain unrelated existing app selection behavior only where its semantics are explicit.
4. Add the browser extension/native-messaging contract and browser support registry. Fail closed with a visible unsupported/permission-required state when no registered extension is connected.
5. Redesign Settings around the fixed sidebar and one scroll pane, including clear target availability and scope controls.
6. Add deterministic tests for settings migration, target/source separation, pause ownership, manual user overrides, multiple sessions and overlap. Build the app and inspect the rendered Settings window.
7. Test local extension fixtures for multiple media sessions and record browser-specific real playback evidence only for browsers available and permitted on this Mac. Do not deploy from this branch.

## Acceptance checks

- Existing ChatGPT speech still pauses or lowers Apple Music according to the chosen mode, and only Oreja-owned changes are restored.
- If microphone speech interruption is enabled, speaking triggers that same configured response.
- Browser target never uses app mute, app termination, or global media keys.
- Browser commands affect only sessions confirmed playing at interruption start; only sessions paused by Oreja can resume; a user pause or resume removes Oreja's ownership.
- Multiple tabs/windows and overlapping interruption events do not duplicate commands or prematurely resume media.
- Browser scope is explicit: all connected supported browsers or the frontmost connected browser at interruption start.
- Unsupported browsers and missing extension/permission states are visible and actionable.
- Settings migration preserves all current features and shows no duplicated or clipped controls at normal and narrow window sizes.
- `./scripts/test.sh` and `./scripts/build.sh` pass. Runtime, real-browser, ChatGPT Voice, and Music tests are reported only when actually run and observed.
- The branch remained reviewable until the user explicitly authorized the 0.4.0 release on
  2026-11-15. That release is experimental; remaining reliability requirements are not implied to be
  complete.
