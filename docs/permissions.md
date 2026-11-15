# Permissions

Oreja needs exactly two macOS capabilities. Both are scoped to the single job and both can be
revoked at any time; the app degrades to "automation off" instead of guessing.

## 1. System audio recording (Core Audio process tap)

**Why:** to know when a selected primary app is producing sound. Oreja creates a private
process tap and reads levels from a copy of that app's output. It does not capture the microphone,
the screen, or other apps.

**What macOS shows:** a consent dialog naming Oreja, usually once per code signature. The app also
declares:

```xml
<key>NSAudioCaptureUsageDescription</key>
<string>Oreja listens to the audio output of the apps you select so it can pause or lower playback
while they speak. Audio is analyzed locally as level only; nothing is recorded, stored, or uploaded.</string>
```

**Pane:** System Settings › Privacy & Security › **Screen & System Audio Recording**.

**Entitlement:** `com.apple.security.device.audio-input` (applied to the ad-hoc build; the hardened
runtime is only enabled for Developer ID builds).

**If denied:** tap creation fails. Oreja enters `permissionRequired`, shows the reason, offers a
button that opens the pane, and does not control Music. No blind resume is attempted.

### Resetting

1. System Settings › Privacy & Security › Screen & System Audio Recording → switch Oreja off, then
   back on (or remove it with “−” and relaunch).
2. Ad-hoc rebuilds change the signature, so macOS may treat `build/Oreja.app` as a new app and ask
   again. This is expected, not a bug.

CLI alternatives (service names vary by macOS version; the Settings UI is authoritative):

```bash
tccutil reset AudioCapture app.oreja.van-gogh
tccutil reset ScreenCapture app.oreja.van-gogh
```

## 2. Automation (Music and experimental Browser target)

**Why:** in release 0.4.0, to pause/resume or change Music's volume, and to pause or lower standard
HTML media in the optional experimental Browser target. Oreja never changes Music tracks, clears its
queue, or launches Music.

**What macOS shows:** an Automation dialog when Oreja reads or controls Music. Browser control may
show a separate dialog for each selected browser. Safari and Chromium-family browsers also require
their JavaScript-from-Apple-Events setting to be enabled. Some protected or custom players may not
respond.

**Pane:** System Settings › Privacy & Security › **Automation** → Oreja → Music.

`Info.plist`:

```xml
<key>NSAppleEventsUsageDescription</key>
<string>Oreja controls Music to pause or lower playback while a primary audio source speaks. It does
not read page content, prompts, or conversations.</string>
```

**Entitlement:** `com.apple.security.automation.apple-events`.

**If denied:** Music or browser control failures are reported in diagnostics. Browser media control
is experimental in release 0.4.0.

### Resetting

```bash
tccutil reset AppleEvents app.oreja.van-gogh
```

Or System Settings › Privacy & Security › Automation → Oreja → toggle Music.

## Permissions Oreja does **not** need

- Microphone unless “Apply the interruption while I speak” is enabled.
- Screen Recording content (only system audio capture, which shares a pane name).
- Accessibility, Input Monitoring, Full Disk Access.
- Root, kernel extensions, developer tools.
- Network access, accounts, or API keys.

## Sandbox and Mac App Store

- The current build is **not sandboxed** and is distributed directly.
- A sandboxed build needs `com.apple.security.device.audio-input` and
  `com.apple.security.automation.apple-events`. Apple Events automation from a sandbox generally
  requires temporary exception entitlements and review justification; process taps have their own
  review considerations.
- Nothing here relies on private APIs or security bypasses. If App Store review rejects the
  automation model, direct distribution with Developer ID signing and notarization remains the
  supported path. Do not remove privacy controls to pass review.

## First-run checklist

1. Launch Oreja; onboarding opens.
2. Choose the ChatGPT desktop app (or a browser, experimental).
3. Choose Apple Music.
4. Grant system audio recording when asked (or via the onboarding button).
5. Approve the Music Automation prompt when Oreja first checks playback.
6. Run the live test: start a ChatGPT voice answer with music playing; the panel should show
   "ChatGPT is speaking", then "Waiting for silence", then music resumes.

Diagnostics lists which permission is missing and which step failed; see `troubleshooting.md`.
