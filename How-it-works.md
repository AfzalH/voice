# SrizonVoice: How It Works

## Onboarding flow (first run / missing API key)

- App starts as a menu-bar-only app (Dock icon hidden) and loads settings from `UserDefaults` and Keychain.
- API key is stored in Keychain; on first launch after migration, any legacy key in `UserDefaults` is moved to Keychain.
- If no API key is found, it opens the setup window automatically.
- Setup includes:
  - Gladia API key field (with link to app.gladia.io)
  - Shortcut recorder
  - Primary language selector (111 languages supported, with country flag emojis)
  - Secondary language selector (optional, with "None" option to deselect)
  - Permission status rows (Microphone + Accessibility) with live polling every second until both are granted
  - "Check Permissions" button
- On Save:
  - API key is validated against Gladia (`POST /v2/live` initialization test — opens a WebSocket and immediately tears it down).
  - A progress indicator and "Validating key..." label appear during validation.
  - If valid, API key + hotkey + language are persisted.
  - Setup closes.
  - If invalid, an error is shown and setup remains open.

## Menu bar

- The status item shows a `mic.fill` SF Symbol when idle.
- Clicking the status item opens a popover with:
  - Start / Stop Dictation button (with shortcut hint)
  - Primary language picker (all 111 Gladia-supported languages with country flags)
  - Secondary language picker (optional, with "None" option)
  - Reconnecting / error status when applicable
  - Settings button
  - "Open Setup" button (only if no API key is saved)
  - Quit button
- `autosaveName` is set so macOS remembers the icon's position across launches.

## Hotkey behavior

- Global hotkey (default: `Cmd+Shift+D`) toggles dictation via Carbon `RegisterEventHotKey`.
- If API key is missing and hotkey is pressed:
  - It does not open setup automatically.
  - It shows: "Add your Gladia API key in Settings."

## Normal dictation flow

- Press hotkey (or menu button) to start dictation.
- App checks Accessibility permission and requests microphone permission if needed.
- It starts a Gladia live session using the selected language.
- A "Tink" system sound plays when dictation starts.
- While dictating:
  - Menu bar icon switches to an animated 3-bar waveform driven by the real-time audio RMS level.
  - If the dictation language is not English, the language code (e.g. "DE", "FR") is shown next to the waveform.
  - A stop panel appears in the top-right corner of the screen (`■ Stop (Esc)`).
- Final transcript text is inserted into the focused app, followed by a trailing space.
- Press hotkey again or `Esc` (global CGEvent tap) to stop.
- A "Pop" system sound plays when dictation stops.

## Audio pipeline

- Microphone audio is captured via `AVAudioEngine` and resampled to 16 kHz mono PCM16.
- Silence detection: chunks below an RMS threshold (0.008) are not sent, saving bandwidth.
- Audio is sent as binary WebSocket frames; if binary fails the client falls back to base64-encoded JSON frames for the rest of the session.

## Language behavior

- Primary and secondary language can be changed in:
  - Onboarding
  - Menu bar language pickers
  - Settings
- If language is changed while dictating, app stops and restarts dictation with the new language.
- 111 languages are supported (all Gladia-supported languages) with country flag emojis for easy identification.
- Secondary language is optional and can be set to "None" to deselect it.
- When a secondary language is selected, code-switching is automatically enabled in Gladia, allowing seamless switching between languages during dictation.
- The language configuration is passed to Gladia as: `{"languages": ["primary", "secondary"], "code_switching": true/false}` (code_switching is enabled only when multiple languages are selected).

## Settings and reopen behavior

- Menu includes Settings and Quit.
- Reopening the app while it is already running opens Settings.
- Settings allows updates to API key, hotkey, and language.
- Saving in Settings re-validates API key before persisting.

## Resilience and fallbacks

- On unexpected WebSocket disconnect, app attempts reconnection up to 3 times (with escalating back-off).
- Text insertion path:
  - Primary: Accessibility (`AXUIElement`) — tries `kAXSelectedTextAttribute` on focused element; if that fails (Notes, Pages, etc.), searches descendant elements recursively; also tries `kAXValueAttribute` for single-line fields
  - Fallback: clipboard + simulated `Cmd+V` paste — posts to frontmost app's PID with proper timestamps (macOS 15+ compatibility); original clipboard restored after 0.35 s
- App attempts launch-at-login registration via `SMAppService` on macOS 13+.
- Error messages auto-dismiss after 5 seconds.
- A programmatic app icon (blue rounded rect + white mic symbol) is generated at launch so the app is recognizable in permission dialogs and Activity Monitor.
