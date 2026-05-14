# Changelog

All notable changes to SrizonVoice will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.1] - 2026-05-14

### Fixed
- Built the installer app as a universal macOS binary so Intel Macs on macOS 12 can install it.

## [3.0.0] - 2026-05-12

### Changed
- Replaced the Groq Whisper transcription and LLM cleanup pipeline with Gemini `gemini-3.1-flash-lite`.
- Settings now save a Gemini API key and output mode for transcription, correction, and translation.
- The menu bar popup now includes output mode and translation language controls.
- Added a custom prompt output mode that is edited in Settings and selectable from the popup.
- Lowered the minimum supported macOS version to 12.0 Monterey.
- Removed spoken-language selection; Gemini now detects source languages from the audio.
- Handsfree recording is now the default, with a 1 minute auto-stop.
- Replaced the handsfree auto-stop text field with a 30 second to 7 minute slider.
- Improved the Correct things prompt to remove fillers, repetitions, false starts, and mumbling artifacts.

### Removed
- Removed post-processing model and prompt settings.
- Removed fast vs. accurate transcription model selection.

## [2.1.0] - 2026-03-20

### Added
- Gemini post-processing support as an alternative to Groq
- Improved post-processing prompt: short phrases and search queries no longer get unwanted capitalization or trailing periods

## [2.0.0] - 2026-02-24

### Changed
- Redesigned settings screen with sidebar navigation and card-based layout
- Human-friendly model names ("Prefer Speed", "Prefer Accuracy") instead of technical names
- Permissions are now requested only when user clicks "Grant Permissions"
- Save/Close buttons hidden until all permissions are granted
- Default post-processing model changed to GPT-OSS 120B
- Input Monitoring permission row shows restart hint and restart button when not granted

### Added
- Settings sidebar with General, Transcription, and Post-Processing tabs
- Separate "Save" and "Save & Close" buttons in settings footer
- Red outline on API key field when empty and all permissions are granted
- App restart button for detecting Input Monitoring permission changes

## [1.0.0] - 2026-02-15

### Added
- Initial release of SrizonVoice
- Global hotkey toggle (default: Cmd+Shift+D) for dictation control
- Gladia Live STT integration (BYOK - Bring Your Own Key)
- Real-time audio capture (16kHz, 16-bit, mono PCM)
- Multi-language support with 111 languages and country flag emojis
- Optional secondary language support with automatic code-switching
- Animated 3-bar waveform icon during dictation
- Language indicator overlay for non-English dictation
- Menu bar language picker for easy switching
- First-run onboarding with API key validation
- Accessibility-based text insertion with clipboard fallback
- Automatic clipboard restoration after paste
- Reconnection handling (up to 3 retries) with UI indicator
- Stop panel with Esc key support
- System sound feedback (Tink on start, Pop on stop)
- Silence detection to optimize bandwidth
- Permission checks for Microphone and Accessibility
- Settings screen for API key, hotkey, and language configuration
- Launch at login support (macOS 13+)
- Programmatic app icon generation
- API key storage in Keychain (migrated from UserDefaults)
- Build and install automation scripts

### Technical
- Built with Swift + SwiftUI for macOS 12+ (Monterey)
- WebSocket streaming to Gladia `/v2/live` API
- Binary WebSocket frames with base64 JSON fallback
- AVAudioEngine-based audio pipeline
- Carbon event hotkey registration
- CGEvent tap for global Esc key handling
- SMAppService for launch-at-login registration

[3.0.1]: https://github.com/AfzalH/voice/releases/tag/v3.0.1
[3.0.0]: https://github.com/AfzalH/voice/releases/tag/v3.0.0
[2.1.0]: https://github.com/AfzalH/voice/releases/tag/v2.1.0
[2.0.0]: https://github.com/AfzalH/voice/releases/tag/v2.0.0
[1.0.0]: https://github.com/AfzalH/voice/releases/tag/v1.0.0
