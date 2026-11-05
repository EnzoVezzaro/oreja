# I built a small Mac tool for the overlap between ChatGPT Voice and Apple Music

I kept reaching for Apple Music whenever a ChatGPT voice reply started. The reply would be clear
enough, but the music was still playing underneath it. After doing that a few too many times, I
made Oreja.

Oreja is a macOS menu bar app. It watches the selected app's output level on the Mac, pauses Apple
Music while the reply is active, and starts it again after the sound has been quiet for a moment.
There is a second mode that lowers Music and restores its previous volume instead.

The app does not need an OpenAI API key or an account. It does not record or transcribe the
conversation. The audio path turns the selected app's output into a short-lived level signal, then
discards the samples. Music control happens through macOS automation.

I wanted the decision-making code to stay boring. The coordinator owns the pause and its release.
The Core Audio and Music integrations sit behind separate adapters. That keeps the part that decides
what should happen independent from the parts that talk to macOS.

The current release supports macOS 14.2 and newer, Apple Music, and the ChatGPT desktop app. Browser
sources are experimental because a browser process can contain more than the ChatGPT tab. The
download is an early ad-hoc-signed preview. I have also not completed a supervised live ChatGPT
Voice test yet, so I am looking for early users rather than calling this finished.

If you use Apple Music while talking to a voice assistant, I would like to hear how the handoff feels
on your Mac. Does Music come back at the right time? Would you prefer pausing it or lowering the
volume? The project and download are here:

- [Oreja on GitHub](https://github.com/EnzoVezzaro/oreja)
- [Oreja website](https://oreja-tau.vercel.app/)

