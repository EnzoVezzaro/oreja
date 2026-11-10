# Product

## Platform

adaptive

## Users

People on macOS who listen to Apple Music while using ChatGPT or another supported AI audio source, especially during voice conversations.

## Product Purpose

Oreja is a local menu bar companion that listens to the selected AI app's audio level and coordinates Apple Music playback around it. It can pause and resume music, or lower music to a chosen level and return it to a chosen level when the conversation becomes quiet. Success means the user can hear the AI clearly without manually managing Music.

## Positioning

Oreja is a small, deterministic audio companion: it reacts to output level, not speech content, does not transcribe conversations, and does not send audio or prompts to a server.

## Operating Context

Oreja runs quietly in the macOS menu bar alongside ChatGPT and Apple Music. The user configures behavior in Settings, then leaves the app running while talking. Manual playback changes always take precedence.

## Capabilities and Constraints

- Supports Apple Music in the current release.
- Listens to any number of selected audio apps at once: AI assistants (ChatGPT, Claude, and any app
  you choose), coding agents and terminals, calls and messages, and video or podcast apps. Browsers
  are marked experimental. Music players can never be selected as a source.
- Supports pause/resume and lower-volume/restore modes.
- Lower-volume mode has independent live controls for the conversation volume and return volume.
- Quiet intervals and conversation hold are configurable and apply live.
- Audio level analysis is local and transient; conversations are not recorded or transcribed.
- Requires macOS 14.2 or newer and the relevant macOS audio, microphone, and automation permissions.
- The current distribution is an ad-hoc signed, not-notarized DMG.
- The source is GPL-3.0-only and Oreja is independent from OpenAI and Apple.

## Brand Commitments

The product name is Oreja de Van Gogh. The current identity uses a listening mark, warm paper and ink, deep indigo, and wheat as a restrained accent. The voice is human, calm, slightly playful, and direct. The product should feel like a small attentive companion, not an enterprise control panel.

## Evidence on Hand

- Current landing page: `site/index.html`.
- Current native UI and tokens: `apps/macos/SettingsView.swift` and `apps/macos/Theme.swift`.
- Current brand notes: `docs/brand.md`.
- Automated suite currently passes 83 tests.
- A macOS 0.1.0 DMG is published from the landing page and attached to the GitHub release.

## Product Principles

1. Make the audio relationship obvious before explaining the machinery.
2. Show the product doing its one job; do not decorate around it.
3. Keep privacy claims concrete and verifiable.
4. Prefer calm control over notification-heavy automation.
5. Preserve user control whenever Oreja and Music disagree.

## Accessibility & Inclusion

The web surface must remain keyboard navigable, readable at common desktop and mobile widths, and legible in light and dark appearances. Native controls should keep macOS accessibility semantics and visible focus states.
