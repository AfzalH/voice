# SrizonVoice

Menu bar dictation app for macOS (Ventura+) using Gladia Live STT (BYOK).

## Run (dev)

```bash
swift run
```

## Build installable app (.app bundle)

```bash
./scripts/build-app.sh
```

This produces:

`dist/SrizonVoice.app`

## Create distributable DMG

```bash
./scripts/create-dmg.sh
```

This produces:

- `dist/SrizonVoice-0.1.0.dmg` — Installer disk image
- `dist/SrizonVoice-0.1.0.sha256` — Checksum for verification

## Install

From DMG (recommended):

1. Open `SrizonVoice-0.1.0.dmg`
2. Drag `SrizonVoice.app` to the `Applications` folder
3. Launch from Applications or Spotlight

From script:

```bash
./scripts/install-app.sh
```

Or manually:

```bash
cp -R "dist/SrizonVoice.app" /Applications/
```

Then launch `SrizonVoice` from Applications or Spotlight.

## What is included

- Global hotkey toggle (`Cmd+Shift+D` by default)
- Mic capture (`16kHz`, `16-bit`, mono PCM) via `AVAudioEngine`
- Gladia `/v2/live` session init + live WebSocket streaming
- Partial transcript overlay panel (non-activating)
- Final transcript insertion with:
  - Accessibility first (`AXUIElement`)
  - Clipboard + simulated paste fallback (clipboard restored)
- Menu bar language selector (111 languages with country flag emojis) and Settings screen
- Optional secondary language support with automatic code-switching
- First-run onboarding (API key, shortcut, permission checks)
- Reconnect handling (up to 3 retries) with UI indicator

## Privacy

SrizonVoice processes audio locally and streams it directly to Gladia's servers using your personal API key. No data passes through Srizon servers. Audio is only sent when you actively trigger dictation.

**Privacy Policy:** [https://www.srizon.com/privacy](https://www.srizon.com/privacy)

## Cleanup

```bash
# 1. Quit the running app (if it's open)
osascript -e 'quit app "SrizonVoice"' 2>/dev/null

# 2. Remove the old app bundle
rm -rf "/Applications/SrizonVoice.app"

# 3. Clear the old UserDefaults (includes the legacy plaintext API key)
defaults delete com.srizon.voice 2>/dev/null
```

## Install new

```bash
./scripts/install-app.sh
```
