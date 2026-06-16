# SrizonVoice

Push-to-talk dictation app for macOS 12 Monterey and later using Gemini audio transcription, automatic spoken-language detection, and optional translation (BYOK).

Press a hotkey to record, press it again to transcribe. Gemini detects the spoken language automatically, then SrizonVoice lets you choose a post-processing action before inserting the final text wherever your cursor was.

SrizonVoice is free. You only pay Google Gemini API usage through your own API key, which should be very low for typical dictation.

## Download

Download the latest installer: [SrizonVoice-3.1.0.dmg](https://github.com/AfzalH/voice/releases/download/v3.1.0/SrizonVoice-3.1.0.dmg).

Checksums and older builds are available on [GitHub Releases](https://github.com/AfzalH/voice/releases/latest).

> [!WARNING]
> **"Apple could not verify" Warning**
>
> Since SrizonVoice is not notarized by Apple yet, macOS Gatekeeper may block the app on first launch. To fix this, open Terminal and run:
>
> ```sh
> xattr -cr /Applications/SrizonVoice.app
> ```
>
> This removes the quarantine flag that macOS adds to downloaded apps. You only need to do this once.

## Setup

1. Get a Gemini API key from [aistudio.google.com](https://aistudio.google.com/apikey)
2. Launch SrizonVoice — Settings opens automatically on first run
3. Enter your Gemini API key and click Save
4. Grant Microphone, Accessibility, and Input Monitoring permissions when prompted

## Usage

- **Press** the hotkey (default: `fn`) to start recording
- **Press** it again to stop recording and transcribe
- **Press Escape** while recording to stop and transcribe in handsfree mode
- Choose a post-processing action from the floating panel, or insert the direct transcript
- Switch to Push to Talk in Settings if you prefer hold-to-record behavior
- The floating island at the top of the screen shows a live waveform while recording and a spinner while transcribing

## Run (dev)

```bash
swift run
```

## Build installable app (.app bundle)

```bash
./scripts/build-app.sh
```

This produces `dist/SrizonVoice.app`.

## Create distributable DMG

```bash
./scripts/create-dmg.sh
```

This produces:

- `dist/SrizonVoice-3.1.0.dmg` — Installer disk image
- `dist/SrizonVoice-3.1.0.sha256` — Checksum for verification

## Install

From DMG (recommended):

1. Open `SrizonVoice-3.1.0.dmg`
2. Drag `SrizonVoice.app` to the `Applications` folder
3. Launch from Applications or Spotlight

From script (also cleans up previous installation first):

```bash
./scripts/install-app.sh
```

## Cleanup

Removes the app, preferences, caches, permissions, and login item:

```bash
./scripts/cleanup-app.sh
```

## What is included

- **Handsfree recording** — default `fn` key starts/stops recording, with Push to Talk still available in Settings
- **Mic capture** — `16kHz`, `16-bit`, mono PCM via `AVAudioEngine`
- **Gemini transcription** — `gemini-3.1-flash-lite` auto-detects the spoken language and returns a direct transcript first
- **Interactive post-processing** — clean up, translate, compact, add emoji, make casual, make formal, make technical, or run a custom prompt before insertion
- **Review loop** — chain multiple post-processing actions, undo the last rewrite, and only auto-insert when the checkbox is enabled
- **Favorite translations** — configure two favorite target languages for one-click translation, with a full language picker still available
- **Saved custom prompts** — define reusable post-processing prompts in Settings or save one from the floating panel
- **Floating recording island** — live animated waveform while recording, spinner while transcribing
- **Text insertion** — Accessibility API first (`AXUIElement`), clipboard + simulated paste fallback (original clipboard restored)
- **Translation language selector** — all major target languages with country flags for translation modes
- **Fn key conflict detection** — warns in Settings if the fn key is assigned to a system function
- **First-run onboarding** — API key, shortcut, and permission checks on launch
- **Launch at login** — registers via `SMAppService` on macOS 13+

## Permissions

- **Microphone** — to capture your voice
- **Accessibility** — to insert text and support clipboard paste fallback
- **Input Monitoring** — to monitor the global hotkey and Escape key

## Privacy

SrizonVoice records audio locally and sends it directly to Gemini using your personal API key. If you choose a post-processing action, the transcript text is also sent to Gemini. No data passes through Srizon servers.

**Privacy Policy:** [https://www.srizon.com/privacy](https://www.srizon.com/privacy)

## Further Reading

See [How-it-works.md](How-it-works.md) for a detailed technical walkthrough of the entire codebase.
