# Changelog

All notable changes to SrizonVoice will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-15

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
- Built with Swift + SwiftUI for macOS 13+ (Ventura)
- WebSocket streaming to Gladia `/v2/live` API
- Binary WebSocket frames with base64 JSON fallback
- AVAudioEngine-based audio pipeline
- Carbon event hotkey registration
- CGEvent tap for global Esc key handling
- SMAppService for launch-at-login registration

[0.1.0]: https://github.com/yourusername/voice/releases/tag/v0.1.0
