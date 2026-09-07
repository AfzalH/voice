# vBoard

Formerly SrizonVoice. Same app, same settings; renamed to match the vBoard apps on iOS and Android.

Push-to-talk dictation app for macOS 12 Monterey and later using Gemini audio transcription, automatic spoken-language detection, and optional translation (BYOK).

Hold a key to dictate (push to talk), or tap another to record handsfree. Gemini detects the spoken language automatically (or follows the language hint you pick in the menu bar), then vBoard lets you choose a post-processing action before inserting the final text wherever your cursor was.

vBoard is free. You only pay Google Gemini API usage through your own API key, which is billed by Google: light use costs cents, heavy daily dictation typically $1–2 a month.

## Download

Download the latest installer: [vBoard-3.6.1.dmg](https://github.com/AfzalH/voice/releases/download/v3.6.1/vBoard-3.6.1.dmg).

Checksums and older builds are available on [GitHub Releases](https://github.com/AfzalH/voice/releases/latest).

> [!WARNING]
> **"Apple could not verify" Warning**
>
The app is signed with a Developer ID certificate and notarized by Apple, so it opens without Gatekeeper warnings.

## Setup

1. Get a Gemini API key from [aistudio.google.com](https://aistudio.google.com/apikey)
2. Launch vBoard — Settings opens automatically on first run
3. Grant Microphone and Accessibility permissions
4. Enter your Gemini API key, choose a model if needed, and click Save

## Usage

- **Hold** the push-to-talk key (default: `fn`) to record, **release** to transcribe and insert. A quick tap or `fn`+another key is ignored, so the key keeps its normal function.
- **Tap** the handsfree key (default: `Right ⌘`) to start recording, tap again or press **Escape** to stop and transcribe
- **Press Escape** while holding push to talk to cancel without transcribing
- Pick the language you are speaking (or **Auto**) from the "Speaking" chips in the menu-bar popover
- Choose a post-processing action from the caret bubble, or insert the direct transcript
- Both shortcuts can be changed or disabled in Settings; left and right modifier keys are distinct
- The floating island at the top of the screen shows a live waveform while recording and a spinner while transcribing

## Run (dev)

```bash
swift run
```

## Build installable app (.app bundle)

```bash
./scripts/build-app.sh
```

This produces `dist/vBoard.app`. The bundle is signed with the first Apple Development / Developer ID identity found in your keychain (override with `CODESIGN_IDENTITY=...`, or `CODESIGN_IDENTITY=-` for ad-hoc). A stable identity is what lets macOS keep the Accessibility and Microphone grants across rebuilds.

## Create distributable DMG

```bash
./scripts/create-dmg.sh
```

This produces:

- `dist/vBoard-3.6.1.dmg` — Installer disk image
- `dist/vBoard-3.6.1.sha256` — Checksum for verification

## Install

From DMG (recommended):

1. Open `vBoard-3.6.1.dmg`
2. Drag `vBoard.app` to the `Applications` folder
3. Launch from Applications or Spotlight

Upgrade in place, keeping settings, history, and permissions:

```bash
./scripts/upgrade-app.sh
```

Fresh install from script (wipes settings and permissions first):

```bash
./scripts/install-app.sh
```

## Cleanup

Removes the app, preferences, caches, permissions, and login item:

```bash
./scripts/cleanup-app.sh
```

## What is included

- **Two shortcuts** — push to talk (hold `fn` by default) and handsfree (tap `Right ⌘` by default), both active at once, each configurable or disableable; side-specific modifiers supported
- **Tap/combination safe** — push to talk ignores quick taps and key combinations so the shortcut key never loses its normal function
- **Spoken language hint** — quick picker of recent (or common/system) languages in the menu bar, with automatic detection as default
- **Mic capture** — `16kHz`, `16-bit`, mono PCM via `AVAudioEngine`
- **Gemini transcription** — `gemini-3.1-flash-lite` by default, with `gemini-3.5-flash` selectable in Settings; both auto-detect the spoken language and return a direct transcript first
- **Interactive post-processing bubble** — clean up, translate, compact, add emoji, make casual, make formal, make technical, or run a custom prompt before insertion
- **Review loop** — chain multiple post-processing actions, undo the last rewrite, and only auto-insert when the checkbox is enabled
- **Copy and Insert** — final text is copied to the clipboard and inserted, so manual paste is available if insertion fails
- **Post-processing bypass** — turn off the floating panel in Settings to copy and insert the direct transcript immediately
- **Favorite translations** — configure two favorite target languages for one-click translation, with a full language picker still available
- **Saved custom prompts** — define reusable post-processing prompts in Settings or save one from the floating panel
- **Floating recording island** — live animated waveform while recording, spinner while transcribing
- **Text insertion** — Accessibility API first (`AXUIElement`), clipboard + simulated paste fallback
- **Translation language selector** — all major target languages with country flags for translation modes
- **Fn key conflict detection** — warns in Settings if the fn key is assigned to a system function
- **First-run onboarding** — API key, shortcut, and permission checks on launch
- **Launch at login** — registers via `SMAppService` on macOS 13+

## Permissions

- **Microphone** — to capture your voice
- **Accessibility** — to insert text and support clipboard paste fallback
- **Input Monitoring** — not normally needed; Accessibility already allows the global shortcut listener. Settings only asks for it if macOS refuses the listener without it.

## Privacy

vBoard records audio locally and sends it directly to Gemini using your personal API key. If you choose a post-processing action, the transcript text is also sent to Gemini. No data passes through Srizon servers.

**Privacy Policy:** [https://www.srizon.com/privacy](https://www.srizon.com/privacy)

## Further Reading

See [How-it-works.md](How-it-works.md) for a detailed technical walkthrough of the entire codebase.
