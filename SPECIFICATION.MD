# SrizonVoice — Specification

## 1. Overview

SrizonVoice is a lightweight, background-running macOS utility that enables voice-to-text dictation in any text field across the operating system. It functions as a "Bring Your Own Key" (BYOK) application, relying on the user's personal Gladia.io Real-time API key. This ensures user privacy, eliminates middleman server costs, and provides direct access to Gladia's enterprise-grade transcription.

**Tech Stack:** Native Swift + SwiftUI, targeting macOS 13+ (Ventura).

**API Reference:** https://docs.gladia.io/chapters/live-stt/quickstart

### Design Philosophy: Opinionated by Default

This app makes decisions so the user doesn't have to. Configuration is limited to things that are genuinely personal or required:

| User controls | App decides (hardcoded) |
|---|---|
| Gladia API key | Audio format (16kHz, 16-bit, mono PCM) |
| Global hotkey shortcut | Model (`solaria-1`) |
| Dictation language | Input device (system default mic) |
| | Launch at login (always on) |
| | Punctuation (always inserted) |
| | Insertion strategy (auto-detects best method) |

If a sensible default exists, ship it. Don't ask the user.

---

## 2. User Flows & Stories

**The "Writer" Flow:** As a user, I want to press a global hotkey while in Microsoft Word or Obsidian to start dictating immediately without bringing up a separate window.

**The "Polyglot" Flow:** As a user, I want to switch from English to Spanish dictation via a quick menu bar toggle so I can reply to international emails effortlessly.

---

## 3. Functional Requirements

### 3.1 Global Trigger & Input

**FR-01 (Global Hotkey):** The app must listen for a user-configurable global shortcut (Default: Cmd+Shift+D).

- Behavior: This acts as a toggle (Push-to-Start / Push-to-Stop).

**FR-02 (Input Focus):** The app must not steal focus when triggered; the cursor must remain in the user's active application (e.g., Slack, Notes, Chrome).

**FR-03 (Visual Feedback):** When active, the menu bar icon must display a small **animated sound wave** (2-3 bars) that responds to the live microphone input level. Louder input = taller/more active bars, silence = minimal idle animation. When inactive, the icon returns to a static microphone glyph.

### 3.2 Gladia API Integration

**FR-04 (Session Initialization):**

- The app must perform a `POST` request to `https://api.gladia.io/v2/live` with the header `x-gladia-key: <API_KEY>`.
- The request body must include audio configuration:
  ```json
  {
    "model": "solaria-1",
    "encoding": "wav/pcm",
    "sample_rate": 16000,
    "bit_depth": 16,
    "channels": 1,
    "language_config": {
      "languages": ["en"],
      "code_switching": false
    },
    "messages_config": {
      "receive_partial_transcripts": true
    }
  }
  ```
- It must extract both `id` (session ID) and `url` (WebSocket URL) from the JSON response.

**FR-05 (WebSocket Connection):**

- The app must establish a Secure WebSocket (WSS) connection to the received `url`.
- It must handle `open`, `message`, `error`, and `close` events robustly.
- On unexpected disconnection, the app must attempt to **reconnect to the same URL** to resume the session (Gladia supports session continuity).
- On intentional stop, the app must send `{"type": "stop_recording"}` before closing, or close the socket with code `1000`.

**FR-06 (Audio Streaming):**

- Audio must be captured via `AVAudioEngine` from the **system default input device** (no device picker — follows macOS Sound settings).
- Format: **16kHz, 16-bit, mono PCM** (matching the init config).
- **Primary method (Binary):** Audio chunks should be sent as raw binary WebSocket frames (lower overhead, preferred).
- **Fallback method (JSON):** If binary framing is unavailable, send as JSON: `{"type": "audio_chunk", "data": {"chunk": "<base64-encoded-audio>"}}`.

**FR-07 (Message Handling):**

- The app must parse incoming JSON messages for `type: "transcript"`.
- It must use the `data.is_final` property to differentiate between **partial** (interim) and **final** transcripts.
- Final transcript text is found at `data.utterance.text`.
- The app must also handle `type: "error"` messages from the server and surface them to the user.

### 3.3 Text Insertion Logic

**FR-08 (Insertion Strategy):**

- **Primary Method:** Use macOS Accessibility APIs (`AXUIElement`) to insert text directly into the focused field (`kAXSelectedTextAttribute`).
- **Secondary Method (Fallback):** If Accessibility insertion fails (common in Electron apps like VS Code), save the current clipboard contents, copy the transcript text to the Clipboard, simulate a `Cmd+V` keystroke, then **restore the original clipboard contents** after a short delay.

**FR-09 (Typing Experience):**

- **Partials:** Do not type partial results into the document (avoids cursor jitter). Display them in a temporary non-activating floating overlay (`NSPanel`) near the text cursor or mouse cursor.
- **Finals:** Insert confirmed text into the document followed by a space.

### 3.4 Multi-Language Support

**FR-10 (Language Selector):** The Menu Bar dropdown must list supported languages.

**FR-11 (Config Update):** Switching languages must stop the current session (send `stop_recording`), then start a new Gladia session with the updated `language_config.languages` parameter.

### 3.5 Error Handling & Resilience

**FR-12 (Network Failure):** If the WebSocket disconnects unexpectedly mid-dictation, the app must:
1. Show a brief "Reconnecting..." indicator in the menu bar / overlay.
2. Attempt to reconnect to the same session URL (Gladia preserves session state).
3. After 3 failed retries, stop the session and notify the user.

**FR-13 (Invalid API Key):** If the `POST /v2/live` init call returns a 401/403, display a clear error prompting the user to check their API key in Settings.

**FR-14 (Session Timeout):** If Gladia closes the WebSocket (code != 1000) due to inactivity or session limits, gracefully end the dictation and inform the user.

---

## 4. UI/UX Requirements

### 4.1 Onboarding Screen (First Run Only)

The app must launch a window if no API key is detected:

- **Welcome Message:** "Bring the power of Gladia AI to your Mac."
- **API Key Input:** A secure text field for the Gladia API Key.
- **Link:** "Get your key from [app.gladia.io](https://app.gladia.io)".
- **Shortcut Config:** A recorder field to set the global hotkey.
- **Permission Check:** Green checkmarks when Microphone and Accessibility permissions are granted.

### 4.2 Settings Menu

Accessible via the Menu Bar > Settings. Kept intentionally minimal:

- **Shortcut:** Change the global hotkey.
- **Language:** Select dictation language.
- **API Key:** Update/Remove Gladia API Key, link to Gladia dashboard.

Everything else (audio format, model, input device, punctuation, launch at login) is decided by the app and not exposed to the user.