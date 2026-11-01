# ChatGPT sources on macOS

Oreja monitors the *application* that produces the AI's voice output. It never reads prompts,
replies, or account data.

## Desktop application (default)

The ChatGPT desktop app has shipped under more than one bundle identifier. Oreja matches:

- prefix `com.openai.`
- and the identifiers `com.openai.chat`, `com.openai.chatgpt`, `com.openai.codex`

Matching the prefix is what makes helper processes count: the process that actually renders audio
often has its own identifier, and `AudioProcessCatalog` resolves processes by identifier prefix.**Observed:** the installed `/Applications/ChatGPT.app` on the test Mac registers as
`com.openai.codex`, and its helpers appear as `com.openai.codex.helper` in the Core Audio process
list. **Unverified:** whether the voice experience renders audio in the main process or a helper;
that requires a live tap during a voice session. See `docs/test-evidence.md`.

## Browser sessions (experimental)

Supported browser identifiers are listed in `AISourceCatalog.browserBundleIdentifiers` (Chrome,
Safari, Edge, Arc, Brave, Firefox). Two caveats, both shown in the UI:

1. A browser tap captures **every tab's** audio, not just ChatGPT.
2. Browser audio may come from a helper process with a different bundle identifier; if the tap
   matches nothing, Oreja reports "source unavailable" rather than silently doing nothing.

Use a dedicated browser window/profile for ChatGPT if you choose this mode.

## What "speaking" means here

Oreja detects *audio activity* from the selected application, using dBFS thresholds with hysteresis.
It does not classify speech. Notifications, UI sounds, or a video in the same browser will look like
the AI speaking. That is a known limitation of the MVP, disclosed in onboarding and the README.

## What Oreja does not do

- It does not join, mirror, or replace your ChatGPT session.
- It does not need an OpenAI API key, account, or subscription of its own.
- It does not receive start/stop events from ChatGPT; there is no public API for that.

## Detecting the right moment

The pause is triggered by the beginning of sustained audio above −45 dBFS, and the resume by 250 ms
of audio below −55 dBFS followed by the user's quiet interval (default 800 ms). Between sentences the
level usually stays above the deactivation threshold or the silence is shorter than the interval, so
a single reply produces one pause and one resume rather than a stutter.
