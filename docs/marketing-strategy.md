# Oreja de Van Gogh — Product marketing strategy

Status: launch strategy and copy kit for the current 0.2.1 early release.

## The job to be known for

Oreja is the quiet macOS companion for people who listen to music while using ChatGPT Voice:

> Your AI talks. Your music listens.

It pauses Apple Music while the selected AI app is producing audio, then resumes it after the
quiet interval. It can also lower and restore Music's volume. It works locally, without an OpenAI
API key, account, recording, transcription, or network service.

The audience is narrow on purpose: Mac users who regularly combine Apple Music and AI voice
conversations, especially developers, writers, researchers, and accessibility-minded users who are
tired of manually managing two audio streams.

## Readiness before public promotion

Do these before a broad launch:

1. Complete and document one supervised live ChatGPT Voice + Apple Music test. The current repo
   explicitly says that this has not been run; marketing must not imply otherwise.
2. Ship a Developer ID signed and notarized build, or label the release very clearly as an early
   technical preview. The current DMG is ad-hoc signed and not notarized.
3. Complete a trademark/name search before investing in press, directories, or paid promotion.
4. Add a simple first-party feedback path on the site: one email address or GitHub issue link,
   with the expected macOS version and source-app details requested.
5. Capture a short screen recording showing the only important moment: AI audio starts, Music
   pauses; AI goes quiet, Music resumes. Do not use a simulated ChatGPT Voice session as evidence.
6. Make the download page state the macOS requirement, permissions, signing status, privacy model,
   and current source-app limitation above the download button.

Until these gates are complete, use an early-adopter / feedback launch rather than “available for
everyone” language.

## Positioning and message hierarchy

Lead with the interruption problem, then explain the mechanism, then earn trust.

1. Problem: “Music keeps playing while your AI voice reply starts.”
2. Outcome: “Oreja pauses Apple Music and brings it back when the reply ends.”
3. Difference: “It reacts to the selected app’s output level, not conversation content.”
4. Trust: “Audio is processed locally and discarded; no recording, transcript, account, or API.”
5. Scope: “macOS 14.2+, Apple Music, ChatGPT desktop first; browser sources are experimental.”

Avoid “AI-powered,” “speech recognition,” “seamless,” “magic,” “fully tested,” or any claim about
live ChatGPT Voice reliability until that test is observed and recorded.

## Channel sequence

### Phase 0 — proof and feedback (week 1)

Publish the landing-page/download improvements, then invite 10–20 Mac users who already use
ChatGPT Voice and Apple Music. Ask each person to complete one task and report:

- Did onboarding explain the two permissions?
- Did Music pause and resume at the expected times?
- Did the app ever pause for a notification or fail to release ownership?
- Would they choose pause/resume or lower/restore volume?

The goal is qualitative evidence and bug discovery, not reach.

### Phase 1 — maker launch (week 2)

1. Product Hunt: schedule only after the build works in production. Use a personal maker account,
   a clear demo, and a first comment that tells the build story. Invite comments and testing;
   never ask for upvotes.
2. Hacker News: submit as `Show HN: Oreja — a local macOS companion that pauses Apple Music
   during AI voice replies`. Keep the post technical, link to the repo, and be ready to answer
   questions about Core Audio process taps, Apple Events, permissions, and privacy.
3. Indie Mac Apps / Mac app directories: submit after the download and install path are clean.
   Directory listings are discovery surfaces, not the main launch.

### Phase 2 — durable discovery (weeks 3–6)

Publish one technical article on the project site or GitHub Pages, then pitch it personally to
Mac-focused writers and newsletters. The strongest editorial angle is not “another AI app”; it is
“a tiny local audio coordination utility, built without an API or recording.” Suggested targets:

- MacStories, for a hands-on Mac utility story;
- Indie Mac Apps, for directory/editorial discovery;
- Swift / macOS developer newsletters and communities, for the Core Audio and Apple Events build;
- privacy-focused Mac communities, for the local-only design.

Do not mass-submit identical copy. Each pitch should mention why that publication’s readers would
care and disclose the current preview status.

### Phase 3 — release-led promotion

Every meaningful release gets one focused story: a measured improvement, a new source, or a
permission/onboarding fix. Reuse the same evidence across the changelog, site, GitHub release,
Product Hunt update, and a short social post. Do not create a new “launch” for cosmetic changes.

## Publish-ready copy

### Product Hunt

**Name:** Oreja de Van Gogh

**Tagline:** Pause Apple Music while your AI voice reply speaks

**Description:** Oreja is a local macOS menu bar companion for ChatGPT Voice and Apple Music. It
pauses music while the selected AI app produces audio, then resumes it after the quiet interval.
No API key, account, recording, transcript, or network service.

**Maker comment:**

I built Oreja for the small but constant friction of using voice AI with music: the reply starts,
the music keeps playing, and I reach for the menu bar again. Oreja watches the selected app’s
output level and coordinates Apple Music around it. It does not listen for meaning, record audio,
or send anything to a server. The coordinator is a deterministic state machine, and the platform
adapters report their capabilities instead of guessing.

This is an early macOS release. It supports Apple Music and ChatGPT desktop first; browser sources
are experimental. I’m looking for people who use both apps every day and can tell me where the
timing, permissions, or recovery behavior breaks.

### Show HN

**Title:** Show HN: Oreja — a local macOS utility that pauses Apple Music during AI voice replies

**Post:**

I made a small Swift 6 macOS menu bar utility for a specific annoyance: listening to Apple Music
while using ChatGPT Voice. Oreja taps the selected app’s output locally, reduces it to a transient
level signal, and lets a deterministic coordinator pause/resume Music or lower/restore its volume.

There is no OpenAI API, account, recording, transcription, analytics, or network service. The
project is split into a platform-neutral coordinator, a Core Audio adapter, and an Apple Events
Music adapter. The repo includes the executable test runner and the audio probe.

Current limits: macOS 14.2+, Apple Music only, ChatGPT desktop as the primary source, browser
sources experimental. The distributed build is currently an early ad-hoc-signed preview, and a
live ChatGPT Voice session still needs supervised verification. Feedback on the permissions and
audio-state edge cases would be especially useful.

### Blog article

**Title:** Why Oreja listens to audio levels instead of conversations

**Opening:**

When music and a voice assistant share a Mac, the problem is not understanding the conversation.
The problem is knowing when one audio stream should briefly get out of the way. Oreja is a small
experiment in solving that problem with less information, not more: it observes the selected app’s
output level, decides whether the audio has the shape of an active reply, and coordinates Apple
Music around that state. It never needs the words, a transcript, or a cloud service.

The rest of the article should explain the process-tap boundary, the speech-shape filter, the
pause-ownership rule, and the honest limits of the current preview. End with the download link and
an invitation to report the Mac model, macOS version, source app, output device, and observed state
transition.

## Outreach email template

Subject: A small local Mac utility for AI voice + Apple Music

Hi [name] — I built Oreja, a small macOS menu bar companion that pauses Apple Music while a
selected AI app is producing audio, then resumes it after the reply quiets down. It processes only
an in-memory output level locally: no API, account, recording, transcript, or analytics.

I thought of [publication] because [specific reason]. The current release is an early preview for
macOS 14.2+ and Apple Music, with ChatGPT desktop as the primary source. I can provide a short
demo, the open-source repo, and the exact verification notes; I will also be clear about what is
not yet measured. Would this be useful for a hands-on Mac utility or developer-tools roundup?

Thanks,
[name]

## Measurement and operating rhythm

Track only what is needed to learn whether the message works. The product itself remains local and
does not gain analytics by default.

- Discovery: referral clicks to the landing page by channel.
- Activation: download clicks, GitHub stars, and completed feedback reports.
- Product value: users who report at least one successful pause/resume session.
- Trust: install/permission questions, uninstall reasons, and privacy questions.
- Retention: repeat GitHub release downloads or update-page visits, if measurable without tracking.

Weekly review: read every issue and reply, group feedback into onboarding, detection, Music control,
distribution, and positioning, then ship the smallest fix that removes the most doubt. The first
success criterion is not a leaderboard position; it is five independent users reporting that Oreja
handled a real conversation without taking control away from them.

## Immediate next actions

- [ ] Run and record the supervised live ChatGPT Voice test.
- [ ] Decide whether to obtain Developer ID signing/notarization before broad promotion.
- [ ] Complete the name/trademark check.
- [ ] Add a feedback contact and preview-status banner to the site.
- [ ] Record the real product demo.
- [ ] Recruit 10–20 testers.
- [ ] Prepare Product Hunt and Show HN drafts in their respective accounts.
- [ ] Submit to Indie Mac Apps and pitch two relevant Mac publications individually.

