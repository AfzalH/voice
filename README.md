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

## Install

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
