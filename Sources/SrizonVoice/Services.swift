import AppKit
import AVFoundation
import ApplicationServices
import Carbon

// MARK: - PermissionManager

final class PermissionManager {
    var microphonePermissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var accessibilityPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    var inputMonitoringPermissionGranted: Bool {
        CGPreflightListenEventAccess()
    }

    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func requestInputMonitoringPermission() {
        CGRequestListenEventAccess()
    }
}

// MARK: - CaretPositionHelper

/// Returns the focused caret's position in screen coordinates, or nil if unavailable.
enum CaretPositionHelper {
    static func getFocusedCaretScreenPoint() -> NSPoint? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focused = focusedRef else { return nil }
        let element = focused as! AXUIElement

        let rect = getCaretBounds(from: element) ?? getElementBounds(from: element)
        guard let rect else { return nil }
        guard rect.origin.x > 0 || rect.origin.y > 0 else { return nil }
        let screenHeight = NSScreen.screens.map(\.frame).reduce(0) { max($0, $1.maxY) }
        guard rect.origin.y < screenHeight - 5 else { return nil }
        return NSPoint(x: rect.midX, y: rect.minY)
    }

    private static func getCaretBounds(from element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeVal = rangeRef as CFTypeRef?,
              CFGetTypeID(rangeVal) == AXValueGetTypeID()
        else { return nil }
        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &cfRange) else { return nil }
        var queryRange = CFRange(location: cfRange.location, length: max(1, cfRange.length))
        var rangeValue: CFTypeRef?
        guard let axRange = AXValueCreate(.cfRange, &queryRange) else { return nil }
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            axRange,
            &rangeValue
        ) == .success, let boundsVal = rangeValue, CFGetTypeID(boundsVal) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func getElementBounds(from element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = positionRef, let sizeVal = sizeRef,
              CFGetTypeID(posVal as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal as CFTypeRef) == AXValueGetTypeID()
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: pos, size: size)
    }
}

// MARK: - DictationCoordinator

final class DictationCoordinator {
    var onAudioLevel: ((Float) -> Void)?
    var onError: ((String) -> Void)?
    var onTranscribing: ((Bool) -> Void)?

    private let settings: UserSettings
    private let insertionService: TextInsertionService
    private let audioCapture = AudioCaptureService()
    private let transcriptionClient = GeminiTranscriptionClient()
    private var isRunning = false

    /// Accumulated audio data from the recording session.
    private var audioBuffer = Data()
    private let bufferQueue = DispatchQueue(label: "voice.audio.buffer")

    init(settings: UserSettings, insertionService: TextInsertionService) {
        self.settings = settings
        self.insertionService = insertionService
    }

    func startRecording() throws {
        guard !isRunning else { return }
        bufferQueue.sync { audioBuffer = Data() }

        try audioCapture.startCapture { [weak self] data in
            self?.bufferQueue.sync {
                self?.audioBuffer.append(data)
            }
        } levelHandler: { [weak self] level in
            self?.onAudioLevel?(level)
        }
        isRunning = true
    }

    /// Stops recording and discards all audio — no transcription is triggered.
    func cancelRecording() {
        guard isRunning else { return }
        audioCapture.stopCapture()
        isRunning = false
        bufferQueue.sync { audioBuffer = Data() }
    }

    func stopRecordingAndTranscribe() async {
        guard isRunning else { return }
        audioCapture.stopCapture()
        isRunning = false

        let recordedAudio = bufferQueue.sync { audioBuffer }
        bufferQueue.sync { audioBuffer = Data() }

        // Get the target app info before transcription (while recording is still fresh)
        let targetApp = NSWorkspace.shared.frontmostApplication
        let targetAppName = targetApp?.localizedName ?? "Unknown App"

        guard !recordedAudio.isEmpty else {
            onError?("No audio recorded.")
            return
        }

        // Build a WAV file from the raw PCM data
        let wavData = buildWAVFile(from: recordedAudio)

        onTranscribing?(true)

        do {
            let transcript = try await transcriptionClient.transcribe(
                apiKey: settings.apiKey,
                audioData: wavData,
                outputMode: settings.outputMode,
                customPrompt: settings.customPrompt,
                targetLanguage: settings.translationLanguage,
                targetAppName: targetAppName
            )

            onTranscribing?(false)

            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            await MainActor.run {
                let success = insertionService.insertText(trimmed)
                if !success {
                    onError?("Unable to insert text in current app.")
                }
            }
        } catch {
            onTranscribing?(false)
            onError?(error.localizedDescription)
        }
    }

    /// Creates a WAV file header + PCM data (16kHz, 16-bit, mono).
    private func buildWAVFile(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = 16_000
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // subchunk1 size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM format
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        header.append(pcmData)
        return header
    }
}

// MARK: - AudioCaptureService

final class AudioCaptureService {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let queue = DispatchQueue(label: "voice.audio.capture")

    /// RMS level below which audio is considered silence and not sent.
    private let silenceThreshold: Float = 0.008

    func startCapture(
        chunkHandler: @escaping (Data) -> Void,
        levelHandler: @escaping (Float) -> Void
    ) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw DictationError.audioFormatCreationFailed
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.queue.async {
                let rms = self.calculateRMS(from: buffer)
                let normalizedLevel = min(max(rms * 25, 0.05), 1.0)
                levelHandler(normalizedLevel)

                guard let convertedData = self.convertToPCM16(buffer: buffer, targetFormat: targetFormat) else { return }
                chunkHandler(convertedData)
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        converter = nil
    }

    private func convertToPCM16(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) -> Data? {
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let targetFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrames) else { return nil }
        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return nil }
        let byteCount = Int(outputBuffer.frameLength) * Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        guard let ptr = outputBuffer.int16ChannelData?.pointee else { return nil }
        return Data(bytes: ptr, count: byteCount)
    }

    private func calculateRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        if frameCount == 0 { return 0 }
        var sum: Float = 0
        for i in 0..<frameCount {
            let value = channelData[i]
            sum += value * value
        }
        return sqrt(sum / Float(frameCount))
    }
}

// MARK: - GeminiTranscriptionClient

final class GeminiTranscriptionClient {
    private struct UploadedFile {
        let uri: String
        let mimeType: String
    }

    private static let model = "gemini-3.1-flash-lite"
    private static let inlineAudioLimitBytes = 14 * 1024 * 1024

    private let session = URLSession(configuration: .default)

    /// Sends audio to Gemini and returns the final dictation text.
    func transcribe(
        apiKey: String,
        audioData: Data,
        outputMode: TranscriptionOutputMode,
        customPrompt: String,
        targetLanguage: LanguageOption,
        targetAppName: String
    ) async throws -> String {
        let prompt = buildPrompt(
            outputMode: outputMode,
            customPrompt: customPrompt,
            targetLanguage: targetLanguage,
            targetAppName: targetAppName
        )

        if audioData.count <= Self.inlineAudioLimitBytes {
            let audioPart: [String: Any] = [
                "inline_data": [
                    "mime_type": "audio/wav",
                    "data": audioData.base64EncodedString()
                ]
            ]
            return try await generateContent(apiKey: apiKey, prompt: prompt, audioPart: audioPart)
        }

        let uploadedFile = try await uploadAudio(apiKey: apiKey, audioData: audioData)
        let audioPart: [String: Any] = [
            "file_data": [
                "mime_type": uploadedFile.mimeType,
                "file_uri": uploadedFile.uri
            ]
        ]
        return try await generateContent(apiKey: apiKey, prompt: prompt, audioPart: audioPart)
    }

    /// Validates a Gemini API key by listing available models.
    static func validateAPIKey(_ apiKey: String) async -> Bool {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func generateContent(
        apiKey: String,
        prompt: String,
        audioPart: [String: Any]
    ) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent") else {
            throw DictationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        audioPart,
                        ["text": prompt]
                    ]
                ]
            ],
            "generation_config": [
                "temperature": 0
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DictationError.invalidResponse }
        try handleGeminiErrorIfNeeded(statusCode: http.statusCode, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.compactMap({ $0["text"] as? String }).first
        else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DictationError.serverError(body.isEmpty ? "Transcription failed." : body)
        }

        return text
    }

    private func uploadAudio(apiKey: String, audioData: Data) async throws -> UploadedFile {
        guard let startURL = URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files") else {
            throw DictationError.invalidURL
        }

        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.setValue("\(audioData.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.setValue("audio/wav", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "file": ["display_name": "SrizonVoice recording"]
        ])

        let (startData, startResponse) = try await session.data(for: startRequest)
        guard let startHTTP = startResponse as? HTTPURLResponse else { throw DictationError.invalidResponse }
        try handleGeminiErrorIfNeeded(statusCode: startHTTP.statusCode, data: startData)

        guard let uploadURLString = uploadURL(from: startHTTP),
              let uploadURL = URL(string: uploadURLString)
        else {
            throw DictationError.serverError("Gemini did not return an upload URL.")
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue("\(audioData.count)", forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.httpBody = audioData

        let (uploadData, uploadResponse) = try await session.data(for: uploadRequest)
        guard let uploadHTTP = uploadResponse as? HTTPURLResponse else { throw DictationError.invalidResponse }
        try handleGeminiErrorIfNeeded(statusCode: uploadHTTP.statusCode, data: uploadData)

        guard let json = try? JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let file = json["file"] as? [String: Any],
              let uri = file["uri"] as? String
        else {
            let body = String(data: uploadData, encoding: .utf8) ?? ""
            throw DictationError.serverError(body.isEmpty ? "Gemini file upload failed." : body)
        }

        let mimeType = (file["mimeType"] as? String) ?? (file["mime_type"] as? String) ?? "audio/wav"
        return UploadedFile(uri: uri, mimeType: mimeType)
    }

    private func uploadURL(from response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            guard "\(key)".caseInsensitiveCompare("x-goog-upload-url") == .orderedSame else { continue }
            return value as? String
        }
        return nil
    }

    private func handleGeminiErrorIfNeeded(statusCode: Int, data: Data) throws {
        guard !(200...299).contains(statusCode) else { return }
        let body = String(data: data, encoding: .utf8) ?? ""
        if statusCode == 400 || statusCode == 401 || statusCode == 403,
           body.contains("API_KEY_INVALID") || body.contains("PERMISSION_DENIED")
        {
            throw DictationError.invalidAPIKey
        }
        throw DictationError.serverError(body.isEmpty ? "Gemini transcription failed." : body)
    }

    private func buildPrompt(
        outputMode: TranscriptionOutputMode,
        customPrompt: String,
        targetLanguage: LanguageOption,
        targetAppName: String
    ) -> String {
        let base = """
        You are transcribing dictation audio for insertion into \(targetAppName).
        Return only the final text. Do not include labels, Markdown, timestamps, explanations, or surrounding quotes.
        Do not answer questions in the audio; transcribe or transform the dictated words only.
        """

        switch outputMode {
        case .asIs:
            return base + "\nTranscribe the speech as-is. Preserve wording, filler words, casing, and punctuation as closely as possible. Do not correct grammar and do not translate."
        case .corrected:
            return base + "\n" + TranscriptionOutputMode.defaultCustomPrompt
        case .customPrompt:
            let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return base + "\n" + (trimmed.isEmpty ? TranscriptionOutputMode.defaultCustomPrompt : trimmed)
        case .translated:
            return base + "\nTranscribe the speech, then output only the translation in \(targetLanguage.plainName) (\(targetLanguage.code))."
        case .originalAndTranslation:
            return base + "\nTranscribe the speech and translate it to \(targetLanguage.plainName) (\(targetLanguage.code)). Output each utterance as: original - translation. Use one line per utterance and use a plain hyphen separator."
        }
    }
}

// MARK: - TextInsertionService

final class TextInsertionService {
    func insertText(_ text: String) -> Bool {
        // For rich-text apps and terminal emulators, prefer clipboard paste
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? ""
        let bundleID = app?.bundleIdentifier ?? ""
        if appName.contains("Notes") || appName.contains("Pages") ||
           bundleID == "com.apple.Terminal" ||
           bundleID.contains("iTerm") ||
           bundleID.contains("alacritty") ||
           bundleID.contains("warp") ||
           bundleID.contains("kitty") ||
           bundleID.contains("wezterm") ||
           appName.contains("Console") ||
           bundleID.contains("Safari") ||
           bundleID.contains("chrome") || bundleID.contains("Chrome") ||
           bundleID.contains("firefox") || bundleID.contains("Firefox") ||
           bundleID.contains("brave") || bundleID.contains("Brave") ||
           bundleID.contains("arc") ||
           bundleID.contains("opera") || bundleID.contains("Opera") ||
           bundleID.contains("edge") || bundleID.contains("Edge") ||
           bundleID.contains("vivaldi") || bundleID.contains("Vivaldi") ||
           bundleID.contains("browser") || bundleID.contains("Browser") ||
           bundleID.contains("slack") || bundleID.contains("Slack") ||
           bundleID.contains("discord") || bundleID.contains("Discord") ||
           bundleID.contains("notion") || bundleID.contains("Notion") ||
           bundleID.contains("linear") ||
           bundleID.contains("figma") ||
           bundleID.contains("electron") || bundleID.contains("Electron") {
            return pasteWithClipboardFallback(text)
        }

        // Try Accessibility API first (works in most text fields)
        if insertWithAccessibility(text) {
            return true
        }

        // Fall back to clipboard paste as universal method
        return pasteWithClipboardFallback(text)
    }

    // MARK: - Accessibility API

    private func insertWithAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard result == .success, let focused = focusedRef else { return false }
        let element = focused as! AXUIElement

        if trySetText(on: element, text: text) { return true }
        if trySetTextInDescendants(of: element, text: text) { return true }
        if trySetValue(on: element, text: text) { return true }
        return false
    }

    private func trySetText(on element: AXUIElement, text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    private func trySetValue(on element: AXUIElement, text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    private func trySetTextInDescendants(of element: AXUIElement, text: String, depth: Int = 0) -> Bool {
        guard depth < 5 else { return false }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef,
              let array = (children as? [AXUIElement])
        else { return false }
        for child in array {
            if trySetText(on: child, text: text) || trySetValue(on: child, text: text) { return true }
            if trySetTextInDescendants(of: child, text: text, depth: depth + 1) { return true }
        }
        return false
    }

    // MARK: - Simulated Keystrokes (universal fallback)

    /// Types text by simulating keyboard events with CGEventKeyboardSetUnicodeString.
    /// Works in Terminal, browser address bars, and other apps where clipboard paste fails.
    private func insertWithKeystrokes(_ text: String) -> Bool {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return false }

        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // CGEventKeyboardSetUnicodeString can handle up to ~20 UTF-16 units per event reliably.
        // We chunk the text to avoid dropped characters.
        let chunkSize = 16
        for start in stride(from: 0, to: utf16.count, by: chunkSize) {
            let end = min(start + chunkSize, utf16.count)
            var chunk = Array(utf16[start..<end])
            let length = chunk.count

            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let keyUp   = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else { return false }

            keyDown.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: 0, unicodeString: &chunk)

            if let pid = pid {
                keyDown.postToPid(pid)
                keyUp.postToPid(pid)
            } else {
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }

            // Small delay between chunks to let the target app process input
            if end < utf16.count {
                Thread.sleep(forTimeInterval: 0.008)
            }
        }
        return true
    }

    // MARK: - Clipboard Paste (for rich-text apps)

    private func pasteWithClipboardFallback(_ text: String) -> Bool {
        guard let savedClipboard = ClipboardSnapshot.capture() else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Thread.sleep(forTimeInterval: 0.05)

        let keyCode = CGKeyCode(kVK_ANSI_V)
        let timestamp = UInt64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))

        guard let cmdDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return false }
        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand
        cmdDown.timestamp = CGEventTimestamp(timestamp)
        cmdUp.timestamp = CGEventTimestamp(timestamp + 1)

        // Post to cghidEventTap (global) — more reliable for Electron apps (Slack, Discord, etc.)
        // which may ignore pid-targeted events.
        cmdDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.02)
        cmdUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            savedClipboard.restore()
        }
        return true
    }
}

// MARK: - ClipboardSnapshot

final class ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    private init(items: [[NSPasteboard.PasteboardType: Data]]) {
        self.items = items
    }

    static func capture() -> ClipboardSnapshot? {
        let pasteboard = NSPasteboard.general
        guard let existing = pasteboard.pasteboardItems else {
            return ClipboardSnapshot(items: [])
        }
        let snapshot: [[NSPasteboard.PasteboardType: Data]] = existing.map { item in
            Dictionary<NSPasteboard.PasteboardType, Data>(uniqueKeysWithValues: item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            })
        }
        return ClipboardSnapshot(items: snapshot)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for payload in items {
            let item = NSPasteboardItem()
            for (type, data) in payload {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
