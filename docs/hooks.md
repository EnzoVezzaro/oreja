# Hooks

Hooks are Oreja's automation surface: *when Oreja does something, run one of your own actions.*
They are the general mechanism — notification sounds are a built-in behavior, not a special case of
hooks — and they are local. Settings → **Hooks** edits them; each hook is one line.

```
When  [Conversation · The AI starts speaking]   Action [Run a Shortcut]  [Notify me…]  [Test]
```

## What fires

Every hook subscribes to one of Oreja's own events. No event contains audio, prompts or replies,
because nothing is transcribed; the detail is a short description of what Oreja itself did.

| Group | Event | Fires when |
| --- | --- | --- |
| Conversation | The AI starts speaking | The speech-shape filter announces activity from the selected source |
| Conversation | The AI stops speaking | That activity window ends |
| Conversation | A notification sound is ignored | A burst is rejected as brief or steady (nothing was paused) |
| Music | Music is paused | Oreja takes ownership of a pause |
| Music | Music is resumed | Oreja gives that ownership back |
| Music | Music volume is lowered | Oreja takes ownership in lower-volume mode |
| Music | Music volume is restored | The original volume is returned |
| Listening | Listening starts | A tap is created for the selected source |
| Listening | Listening fails | The tap fails, the source quits, or the provider is unavailable |
| Listening | A permission is missing | Audio capture or automation was denied |
| System | The Mac goes to sleep | Sleep notification received |
| System | The Mac wakes up | Wake notification received |

Ownership events fire on the *transition*, not on every state refresh, so a hook bound to "Music is
paused" runs once per owned pause even though the panel repaints constantly.

## What a hook can do

| Action | Fields | Notes |
| --- | --- | --- |
| Run a Shortcut | Shortcut name, exactly as it appears in the Shortcuts app | `shortcuts run "<name>"` with the event as input text, e.g. `speechStarted: The AI source started speaking` |
| Open a URL | Any URL with a scheme | Opens with the default handler. `shortcuts://run-shortcut?name=…` is a shortcut in one line; an app link or a web page works the same way |

There is no shell, no embedded scripting language and no network client inside Oreja. A Shortcut can
run a shell script, call a web API, control HomeKit or write a file if you want that — outside a
process that holds audio-capture permission.

Examples that need nothing but what ships with macOS:

- **Know why the music stopped.** Shortcut with "Show Notification", bound to *The AI starts speaking*.
- **Pause another player.** Shortcut that runs `osascript` against VLC, bound to *Music is paused*.
- **Dim the lights.** Shortcut with a Home action, bound to *The AI starts speaking*.
- **A log of what Oreja did.** Shortcut with "Append to Text File", bound to *Music is paused* and
  one more bound to *Music is resumed*.

## Safeguards

- A hook with no shortcut name or no URL scheme is a **draft**. It is saved and shown, and never fires.
- A disabled hook never fires; **Test** is disabled too.
- Each hook has a **cooldown** (2 s by default). A rapid exchange cannot spawn a burst of shortcuts;
  skipped runs appear in Diagnostics as `Skipped hook … cooling down`.
- One run per hook at a time. A second event while the first is still running is skipped, not queued.
- At most **8 hooks** run for a single event.
- A failing action is reported once, in Diagnostics, as `Hook “…” failed on …`. It is not retried,
  because a missing shortcut is not a transient error.
- **Test** runs the hook immediately and reports what actually happened in Diagnostics; it is the
  only honest way to claim an automation works.

## Privacy

Hooks receive the event name and a short description of Oreja's own action. They never receive
audio, prompts, replies, transcripts or track names. Whatever your shortcut or URL does with that is
outside Oreja — including its permissions and its network access.

## Where this lives in the code

- `packages/OrejaCore/Sources/OrejaCore/Hooks/Hooks.swift` — `OrejaEvent`, `HookAction`, `Hook`,
  `HookContext`, the `HookExecuting` port and `HookDispatcher` (portable, unit-tested).
- `apps/macos/HookExecutor.swift` — the macOS implementation: `shortcuts run` and `NSWorkspace`.
- `apps/macos/AppModel.swift` — fires events from the coordinator, the monitor and system sleep/wake,
  and exposes add / update / remove / test to Settings.
- `apps/macos/SettingsView.swift` — the editor.
