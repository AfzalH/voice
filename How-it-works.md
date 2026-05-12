# How SrizonVoice Works

SrizonVoice is a macOS menu bar app that lets you dictate text into any application by pressing a hotkey. Press once to record, press again to transcribe with Gemini and insert the text wherever your cursor is.

---

## Table of Contents

1. [High-Level Flow](#high-level-flow)
2. [App Entry Point & Menu Bar](#app-entry-point--menu-bar)
3. [Hotkey Detection](#hotkey-detection)
4. [Recording](#recording)
5. [Transcription](#transcription)
6. [Text Insertion](#text-insertion)
7. [The Recording Island UI](#the-recording-island-ui)
8. [Settings & Persistence](#settings--persistence)
9. [Permissions](#permissions)
10. [Threading Model](#threading-model)
11. [Error Handling](#error-handling)

---

## High-Level Flow

```
User presses hotkey
  → Audio capture starts (16kHz PCM, mic)
  → Floating recording island appears with live waveform

User presses hotkey again
  → Audio capture stops
  → PCM data wrapped into WAV file
  → WAV sent to Gemini with the selected output prompt
  → Final dictation text returned
  → Text inserted at cursor (via Accessibility API or clipboard paste)
  → Island disappears

User presses Escape (while recording)
  → In handsfree mode, recording stops and transcribes
  → In push-to-talk mode, recording is cancelled without transcription
```

---

## App Entry Point & Menu Bar

**Files:** `SrizonVoiceApp.swift`, `AppDelegate.swift`

The app uses `@main` on `SrizonVoiceApp` (a SwiftUI `App`), but immediately hands off to an `NSApplicationDelegate` for everything meaningful. The activation policy is set to `.accessory` — no dock icon appears, and the app only lives in the menu bar.

### Status Item

A variable-length `NSStatusItem` is created with a microphone icon (`mic.fill`, SF Symbol, rendered as a template image so it respects light/dark mode). Clicking it toggles an `NSPopover` containing `MenuBarContentView`.

### Icon Animation During Recording

While recording, `AppDelegate` observes `AppModel.$isDictating`. When it becomes `true`, a repeating timer fires at ~8 Hz (0.12s interval). Each tick calls `makeWaveformImage(level:tick:)`, which draws an 18×18pt image of three animated bars whose heights are driven by the real-time audio level and a per-bar phase offset. The image is set as the status item button's image, giving a live waveform in the menu bar itself. When recording stops, the static mic icon is restored.

### First Launch

If no API key is saved, the settings window opens automatically on launch so the user can configure the app before using it.

---

## Hotkey Detection

**File:** `InputMonitors.swift`

The app supports two fundamentally different kinds of hotkeys: regular key + modifier combinations (e.g. `⌥Z`), and the bare Fn key. Each requires a different OS mechanism.

### Regular Hotkeys — Carbon Event Handler

For standard key + modifier combos, the app uses Carbon's `RegisterEventHotKey` API. This registers a system-wide hotkey that fires even when the app is not focused. The event handler is installed on the application event target and listens for `kEventHotKeyPressed`. When triggered, it fires the `onKeyDown` callback.

**Key-up detection** cannot be done through Carbon (it only delivers press, not release). Instead, immediately after `onKeyDown` fires, a CGEvent tap is created listening for `keyUp` events. The tap matches on the registered key code. When the matching key-up arrives, `onKeyUp` fires and the tap is torn down.

```
RegisterEventHotKey → kEventHotKeyPressed → onKeyDown() → create CGEvent keyUp tap
                                                                    ↓
                                                          keyUp event → onKeyUp() → tear down tap
```

### Fn Key — flagsChanged CGEvent Tap

The Fn key (key code 63, `kVK_Function`) is a modifier key — it never fires `keyDown` or `keyUp` events. Instead, it fires `flagsChanged` events whenever the set of held modifier keys changes. Carbon's hotkey API cannot intercept it.

The app creates a permanent CGEvent tap listening for `flagsChanged` events. Inside the callback:

1. Filter to only events with `keyboardEventKeycode == 63` (ignore Shift, Control, etc. firing their own flagsChanged events).
2. Check if `CGEventFlags.maskSecondaryFn` is set in the event's flags.
3. If the flag just appeared and wasn't set before → key was pressed → fire `onKeyDown`.
4. If the flag just disappeared and was set before → key was released → fire `onKeyUp`.

A `fnKeyIsDown: Bool` property tracks the previous state to avoid duplicate callbacks when other modifiers change while Fn is held.

### Escape Key — GlobalEscapeKeyMonitor

A separate, always-on CGEvent tap listens for `keyDown` events with key code 53 (Escape). When detected while recording is active, it cancels the recording without transcribing.

### Why CGEvent Taps Instead of NSEvent.addGlobalMonitorForEvents

The app uses listen-only CGEvent taps for hotkey and Escape monitoring so events are observed without being suppressed or blocked. On current macOS versions, the app checks Input Monitoring before registering those global taps and asks the user to grant it during setup.

---

## Recording

**Files:** `Services.swift` → `DictationCoordinator`, `AudioCaptureService`

### AudioCaptureService

Uses `AVAudioEngine` to capture from the system microphone. The input node's native format (whatever the mic reports — typically 44.1kHz or 48kHz float32) is captured in 2048-frame chunks via an installed tap.

Each chunk is converted to **16kHz, 16-bit, mono PCM** using `AVAudioConverter`. This keeps file sizes small before the audio is wrapped as WAV for Gemini. The conversion ratio is computed as `targetSampleRate / inputSampleRate`, with a small headroom (+32 frames) in the output buffer to account for rounding.

Simultaneously, the RMS (root mean square) amplitude of each input chunk is computed:

```
rms = sqrt( sum(sample²) / frameCount )
```

This is normalized to a 0.0–1.0 range (`min(max(rms * 6, 0.02), 1.0)`) and sent to the UI for the waveform animation.

### DictationCoordinator

Owns the audio capture service and accumulates chunks into an in-memory `Data` buffer. A serial `DispatchQueue` serializes all writes to the buffer so chunks from the audio tap (which arrive on a background thread) don't race with the read that happens at stop time.

`startRecording()` clears the buffer and starts capture. `stopRecordingAndTranscribe()` stops capture, snapshots the buffer, and hands it off to the transcription pipeline.

### WAV File Construction

The raw PCM buffer is wrapped into a proper WAV file before upload. The header is constructed manually:

```
RIFF + total size
WAVE marker
fmt  chunk: PCM format, 1 channel, 16000 Hz sample rate, 32000 byte rate, 2 block align, 16 bits/sample
data chunk: size + raw PCM bytes
```

All multi-byte integers are little-endian, matching the WAV specification.

---

## Transcription

**Files:** `Services.swift` → `GeminiTranscriptionClient`, `Models.swift` → `TranscriptionOutputMode`

### GeminiTranscriptionClient

Sends a `POST` request to Gemini's `generateContent` endpoint with the model `gemini-3.1-flash-lite`:

```
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent
x-goog-api-key: {apiKey}
Content-Type: application/json
```

For normal recordings, the WAV bytes are sent inline as base64 audio:

| Field | Value |
|---|---|
| `contents.parts[].inline_data.mime_type` | `audio/wav` |
| `contents.parts[].inline_data.data` | Base64 WAV bytes |
| `contents.parts[].text` | Prompt for the selected output mode |
| `generation_config.temperature` | `0` |

If the WAV is too large for an inline request, it is first uploaded through Gemini's resumable Files API and then referenced with `file_data` in the `generateContent` request.

The response text is extracted from `candidates[].content.parts[].text` and inserted directly. There is no second cleanup request.

### Output Modes

Gemini receives one prompt tailored to the selected mode:

| Mode | Behavior |
|---|---|
| As is | Transcribes without intentional correction or translation |
| Correct things | Removes filler sounds, hesitation words, repetition, false starts, and mumbling artifacts, then returns grammatically corrected sentences |
| Custom prompt | Uses the saved custom instruction from Settings, initially seeded with the Correct things prompt |
| Translate to target language | Outputs only the target-language translation |
| Original + target translation | Outputs `original - translation`, one utterance per line |

### API Key Validation

When saving settings, the key is validated by making a `GET` request to `https://generativelanguage.googleapis.com/v1beta/models` with the provided key in the `x-goog-api-key` header. A 2xx response means the key is accepted.

---

## Text Insertion

**File:** `Services.swift` → `TextInsertionService`

After transcription, the text needs to appear at the cursor in whatever app is frontmost. Two strategies are attempted in order.

### Strategy 1 — Accessibility API

The macOS Accessibility API lets the app directly write text into focused UI elements:

1. Get the system-wide `AXUIElement`.
2. Query `kAXFocusedUIElementAttribute` to find the element the user is typing into.
3. Set `kAXSelectedTextAttribute` on that element with the transcript. This replaces any selected text and inserts at the cursor, exactly as if the user had typed it.
4. If that fails, walk up to 5 levels of child elements looking for a text-insertion point, trying both `setSelected` and `setValue`.

This is the most accurate method — it preserves undo history in most apps and doesn't touch the clipboard.

### Strategy 2 — Clipboard Paste Fallback

For apps where the AX API doesn't work well (Notes and Pages skip straight to this path, as they're more reliable this way):

1. **Snapshot the clipboard.** All current pasteboard items and their data types (plain text, HTML, RTF, images, etc.) are captured and saved in memory.
2. Clear the pasteboard and write the transcript as plain text.
3. Wait 50ms for clipboard propagation.
4. **Synthesize a Cmd+V keystroke** using `CGEvent`:
   - Create a key-down event for key code `kVK_ANSI_V` with `.maskCommand` flag.
   - Create a matching key-up event.
   - Post both events to the frontmost app's process.
   - Wait 20ms between events.
5. **Restore the original clipboard** 500ms later via `DispatchQueue.main.asyncAfter`, preserving whatever the user had copied before.

---

## The Recording Island UI

**File:** `Panels.swift` → `RecordingIslandController`, `RecordingIslandView`

### The Panel

A frameless `NSPanel` positioned at the **top center** of the screen, 48pt below the top edge (sitting just below the menu bar / notch area). It is 320×36pt. Key configuration:

- `.nonactivatingPanel` — showing it doesn't steal focus from the app you're dictating into.
- `.statusBar` window level — floats above other windows.
- `.canJoinAllSpaces` — visible on all Spaces.
- `backgroundColor = .clear`, `isOpaque = false` — transparent outside the drawn pill shape.

### Visual States

**Recording (waveform):**

A black pill with 85% opacity contains 30 animated bars. The bars are updated by a `CVDisplayLink` synchronized to the display's refresh rate (up to 120Hz on ProMotion displays). Each tick:

1. The ring buffer of 30 bar heights shifts left, dropping the oldest value.
2. A new value is computed: `audioLevel * 0.8 + random(±0.08)`, clamped to [0.08, 1.0].
3. Each bar is colored with a gradient that transitions left-to-right: coral → purple → blue (RGB-interpolated per bar index).
4. Bars are drawn as rounded rectangles, centered vertically in the pill.

**Transcribing (spinner):**

A "Transcribing" label with an animated ellipsis (`.` → `..` → `...` → blank) cycling every 0.4 seconds. A 270° arc on the left rotates 90° with each dot step, creating a loading spinner effect.

---

## Settings & Persistence

**File:** `Models.swift` → `UserSettings`, `HotKey`, `TranscriptionOutputMode`

All settings are stored in `UserDefaults.standard`:

| Key | Type | Default |
|---|---|---|
| `gemini.apiKey` | String | `""` |
| `app.hotKey` | JSON-encoded `HotKey` | Fn key |
| `dictation.outputMode` | String | `"corrected"` |
| `dictation.customPrompt` | String | Correct things prompt |
| `dictation.translationLanguage` | String (ISO code) | `"en"` |
| `app.recordingMode` | String | `"handsfree"` |
| `app.handsfreeMaxSeconds` | Int | `60` |

`HotKey` is a `Codable` struct with `keyCode`, `modifiers`, and `isFnKey`. The custom `init(from:)` decodes `isFnKey` with `decodeIfPresent` defaulting to `false`, so older saved hotkeys without that field continue to work.

### Fn Key Conflict Detection

In Settings, when the selected hotkey is the Fn key, the app reads `AppleFnUsageType` from the `com.apple.HIToolbox` UserDefaults domain. This key reflects what macOS has assigned to the Globe/Fn key in System Settings → Keyboard:

| Value | System Assignment |
|---|---|
| 0 | Do Nothing (no conflict) |
| 1 | Change Input Source |
| 2 | Show Emoji & Symbols |
| 3 | Start Dictation |

If the value is non-zero, a yellow warning appears in the Shortcut section telling the user what the Fn key is currently assigned to and suggesting they either pick a different shortcut or change the assignment in System Settings.

### HotKey Recorder

The settings shortcut field is an `NSButton` wrapped in `NSViewRepresentable`. Clicking it enters recording mode and installs a local event monitor for both `.keyDown` and `.flagsChanged` events:

- **Fn key:** detected via `.flagsChanged` with `keyCode == 63` and `.function` in the modifier flags. Stored as `HotKey(keyCode: 63, modifiers: 0, isFnKey: true)`.
- **Regular combo:** requires at least one of Cmd/Shift/Option/Control to be held. The key code and modifier flags are captured and converted to Carbon's modifier format via `KeyCodeMap.carbonModifiers()`.

---

## Permissions

The app requires three permissions. None are optional for normal operation.

### Microphone

Declared via `NSMicrophoneUsageDescription` in Info.plist. Requested at the first dictation attempt using `AVCaptureDevice.requestAccess(for: .audio)`. Permission status is polled while the Settings window is open so the indicator updates live as the user grants access.

### Accessibility

Declared via `NSAccessibilityUsageDescription`. Checked via `AXIsProcessTrusted()`. Required for:

- Inserting text via the AX API.
- Synthesizing Cmd+V keystrokes for the clipboard fallback.

The system prompt dialog is triggered by calling `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt = true`. Status is also polled while Settings is open.

### Input Monitoring

Checked with `CGPreflightListenEventAccess()` and requested with `CGRequestListenEventAccess()`. Required for global hotkey and Escape monitoring.

---

## Threading Model

| Component | Thread |
|---|---|
| `AppModel` state mutations | `@MainActor` (main thread) |
| `AppDelegate` UI operations | Main thread |
| Audio capture tap callback | `AudioCaptureService.queue` (serial background) |
| Audio buffer writes | `DictationCoordinator.bufferQueue` (serial background) |
| Gemini API requests | Swift concurrency default executor (background) |
| CVDisplayLink waveform callback | Display link thread → dispatched to `@MainActor` |
| Permission polling | Swift concurrency async loop with `Task.sleep` |

Callbacks from background components (`onAudioLevel`, `onError`, `onTranscribing`) are bridged to the main thread inside `AppModel` using `Task { @MainActor in ... }` blocks.

---

## Error Handling

Errors are surfaced as a brief message in the menu bar popover. Most auto-dismiss after 5 seconds; errors that require user action (missing or invalid API key) persist until resolved.

| Scenario | Behavior |
|---|---|
| API key not set | Error shown, Settings opened |
| Accessibility not granted | Error shown, permission prompt triggered |
| Microphone not granted | Permission requested asynchronously |
| Empty recording (silence only) | Silent return — no error, no API call |
| Gemini API 401/403 | "Invalid API key. Check Settings." |
| Gemini API other error | Server error message shown verbatim |
| Text insertion failed | "Unable to insert text in current app." |
| Audio format error | "Could not configure audio capture." |
