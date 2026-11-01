# Troubleshooting

Start with the menu bar panel; it shows one state and a reason. **Settings › Diagnostics** (or the
panel's Diagnostics button) lists recent state transitions and a connection test with per-step
results. Use that before guessing.

## Menus and states

| State | Meaning | If it stays there |
| --- | --- | --- |
| Automation off | The switch is off; Oreja does nothing | Turn it on |
| Looking for the AI source | Automation is on but no monitor is running | Open ChatGPT; make sure the selected app is the one running |
| Monitoring ChatGPT | Monitor is alive, AI is quiet | Ask ChatGPT a question and watch for "ChatGPT is speaking" |
| Music playing | AI is quiet and music is playing | Normal while ChatGPT is silent |
| ChatGPT is speaking | Activity detected; music should be paused | If music is still playing, check Automation permission for Music |
| Music paused by Oreja | Oreja owns the pause | It resumes after the quiet interval |
| Waiting for silence | AI stopped; counting the resume delay | Increase/decrease the resume delay in Settings |
| Resuming music | Resume command in flight | A failure here is shown with a reason |
| Suspended | Mac slept | Wake the Mac; state reconciles automatically |
| Permission required | Audio capture or Automation is denied | See below |
| Needs attention | Repeated command failures or a monitor error | Open Diagnostics; Retry after fixing |

## "Permission required" for audio

Symptom: panel says Oreja cannot capture audio; diagnostics mentions OSStatus -50 or -4.

1. Open System Settings › Privacy & Security › Screen & System Audio Recording.
2. Enable Oreja (or remove it with “−” and relaunch Oreja to prompt again).
3. Restart Oreja after changing the setting.
4. If you rebuilt the app, macOS may treat it as a new app: its ad-hoc signature changed. Grant
   again.

Do not grant Microphone or Accessibility; they are not used.

## "Apple Music needs automation permission"

Symptom: monitoring works, but music never pauses; diagnostics records a permission error.

1. System Settings › Privacy & Security › Automation → Oreja → enable Music.
2. Or run `tccutil reset AppleEvents app.oreja.van-gogh`, quit Oreja, relaunch, and approve the
   prompt on the next check.
3. Keep Music running. Oreja deliberately never launches it.

## Music comes back in the middle of a conversation

Symptom: the assistant stops to work on its answer and music starts again before it speaks.

Oreja reacts to audio, not to the assistant's internal state, so the only thing that holds playback
through a silent stretch is time. **Settings › Keep music paused through a whole conversation**
controls it: raise the seconds until your longest "thinking" pause is covered (30–45 s is comfortable
for long answers), or lower it if you want music back sooner after a quick question. Turning it off
restores the per-reply resume delay.

## Music is playing but Oreja does not pause it

- Check that the **AI source** selection matches the app that is talking. ChatGPT app vs. browser is
  a common mismatch; a browser that renders audio in a helper process needs its audio-process prefix
  (ego lite renders in `com.citrolabs.ego.helper`, Chrome in `com.google.Chrome.helper`). Verify with
  `build/bin/oreja-probe --bundle <prefix> --list` while the app is speaking.
- Check that Music is actually the app playing (not Spotify, not a browser tab).
- Watch Diagnostics for activity events. If no activity appears, the tap is not receiving audio:
  verify with the probe (below), then re-grant audio capture.
- If activity appears but no pause is issued, Music was already paused, a command is pending, or a
  manual override was detected. Diagnostics says which.

## No activity detected with the probe

```bash
./scripts/build.sh --probe
./build/bin/oreja-probe --list
```

Find the target process and confirm `output=yes`. Then:

```bash
./build/bin/oreja-probe --bundle com.openai. --seconds 10
```

- "No matching audio processes": ChatGPT is not currently registered as an audio process. Start a
  voice answer or play a sound in the app.
- Tap creation failed with -50/-4: audio-capture permission is missing for the terminal/app running
  the probe. Grant it and retry.
- Tap starts but no levels: the app is silent, or the wrong process was selected. Use `--pid` with a
  process that shows `output=yes`. CLI tools often have no bundle identifier.

The probe prints levels only. It never stores audio.

## Music keeps toggling

- Increase **resume delay** (Settings). Speech pauses shorter than the delay keep music paused.
- If the AI source is a browser, other tabs and notification sounds can trigger activity. Switch to
  the desktop app or use a dedicated browser window/profile.
- Increase the activity onset debounce only in code/policy if you are building from source; it is
  not exposed in the UI.

## Oreja left my music paused

- If Oreja is running and still owns the pause, turn automation off (or use "Resume my music now").
  The pause is restored first.
- If Oreja crashed, relaunch it. The pause journal restores playback only when the same track is
  still paused and the pause is younger than 12 hours.
- If Music was quit or the track changed meanwhile, Oreja deliberately leaves playback alone. Press
  play in Music.

## App does not appear in the menu bar

- It is a menu bar app with no Dock icon by design; look for the ear glyph.
- If the icon is hidden because the menu bar is full, quit other menu bar apps or use a menu bar
  manager.
- Launch it from Terminal to see errors: `build/Oreja.app/Contents/MacOS/Oreja`.

## Gatekeeper blocks the app on another Mac

The build is ad-hoc signed and not notarized. Either build locally or open
System Settings › Privacy & Security and choose "Open Anyway" after the first blocked launch. Do not
disable Gatekeeper globally. See `distribution.md`.

## Reset everything

```bash
defaults delete app.oreja.van-gogh
tccutil reset AudioCapture app.oreja.van-gogh
tccutil reset AppleEvents app.oreja.van-gogh
```

Then relaunch and complete onboarding.

## Diagnostics content

The log holds Oreja's own state transitions (monitor start/stop, permission errors, ownership
changes, command outcomes) in a 300-event memory buffer and mirrors them to
`~/Library/Logs/Oreja/oreja.log` (rotated at ~1 MB). It never contains audio, prompts, responses, or
transcripts. Use "Clear" to reset the in-app list.

```bash
tail -40 ~/Library/Logs/Oreja/oreja.log     # what Oreja actually did, with timestamps
```

## macOS is waiting for an answer from you

A rebuild changes the app's ad-hoc signature, so the System Audio Recording grant no longer matches
and macOS asks again the next time the app starts monitoring. The permission call blocks until it is
answered, which looks like "Oreja does nothing" — no activity, no pause, and the last log line is
`Starting audio monitor for …`. Look for the dialog (it may be behind other windows) and choose
Allow. Sign a build with a stable identity to avoid the prompt on every build.

## The menu says "Looking for the AI source"

That is the waiting state: the selected app is running but has no audio process yet. ChatGPT only
registers one once a voice session actually produces sound, and the app closes it again when the
session ends. Oreja retries every three seconds and starts the moment the process appears, so no
action is needed — if it never leaves this state, the source selection is usually wrong (App vs.
browser).
