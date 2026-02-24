# SrizonVoice

Menu bar dictation app for macOS (Ventura+) using Groq Whisper (BYOK).

Hold a hotkey while speaking, release to transcribe. Text is inserted wherever your cursor is.

## Download

Download the latest DMG from [GitHub Releases](https://github.com/AfzalH/voice/releases/latest).

## Setup

1. Get a free API key from [console.groq.com](https://console.groq.com/keys)
2. Launch SrizonVoice — Settings opens automatically on first run
3. Enter your Groq API key and click Save
4. Grant Microphone and Accessibility permissions when prompted

## Usage

- **Hold** the hotkey (default: `fn`) while speaking
- **Release** to stop recording and transcribe
- **Press Escape** while recording to cancel without transcribing
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

- `dist/SrizonVoice-2.0.0.dmg` — Installer disk image
- `dist/SrizonVoice-2.0.0.sha256` — Checksum for verification

## Install

From DMG (recommended):

1. Open `SrizonVoice-2.0.0.dmg`
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

- **Press-and-hold hotkey** — default `fn` key, fully customizable in Settings
- **Mic capture** — `16kHz`, `16-bit`, mono PCM via `AVAudioEngine`
- **Groq Whisper transcription** — single batch request, no polling
- **Two model options:**
  - `whisper-large-v3-turbo` — fast (default)
  - `whisper-large-v3` — more accurate
- **Floating recording island** — live animated waveform while recording, spinner while transcribing
- **Text insertion** — Accessibility API first (`AXUIElement`), clipboard + simulated paste fallback (original clipboard restored)
- **Language selector** — 107 languages with country flags, selectable from the menu bar
- **Fn key conflict detection** — warns in Settings if the fn key is assigned to a system function
- **First-run onboarding** — API key, shortcut, and permission checks on launch
- **Launch at login** — registers via `SMAppService`

## Permissions

- **Microphone** — to capture your voice
- **Accessibility** — to insert text and monitor the hotkey (no Input Monitoring permission required)

## Privacy

SrizonVoice records audio locally and sends it directly to Groq's servers using your personal API key. No data passes through Srizon servers. Audio is only sent when you actively trigger dictation.

**Privacy Policy:** [https://www.srizon.com/privacy](https://www.srizon.com/privacy)

## Further Reading

See [how-it-works.md](how-it-works.md) for a detailed technical walkthrough of the entire codebase.
