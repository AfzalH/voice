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
    private let groqClient = GroqTranscriptionClient()
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

        guard !recordedAudio.isEmpty else {
            onError?("No audio recorded.")
            return
        }

        // Build a WAV file from the raw PCM data
        let wavData = buildWAVFile(from: recordedAudio)

        onTranscribing?(true)

        do {
            let transcript = try await groqClient.transcribe(
                apiKey: settings.apiKey,
                audioData: wavData,
                model: settings.transcriptionModel,
                language: settings.language.code
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

// MARK: - GroqTranscriptionClient

final class GroqTranscriptionClient {
    private let session = URLSession(configuration: .default)
    private let endpoint = "https://api.groq.com/openai/v1/audio/transcriptions"

    /// Sends audio to Groq's Whisper API and returns the transcript.
    func transcribe(
        apiKey: String,
        audioData: Data,
        model: TranscriptionModel,
        language: String
    ) async throws -> String {
        guard let url = URL(string: endpoint) else { throw DictationError.invalidURL }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(
            boundary: boundary,
            audioData: audioData,
            model: model.rawValue,
            language: language
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DictationError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw DictationError.invalidAPIKey }
        guard (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String
        else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DictationError.serverError(body.isEmpty ? "Transcription failed." : body)
        }
        return text
    }

    /// Validates a Groq API key by hitting the models list endpoint.
    static func validateAPIKey(_ apiKey: String) async -> Bool {
        guard let url = URL(string: "https://api.groq.com/openai/v1/models") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode != 401 && http.statusCode != 403
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func buildMultipartBody(
        boundary: String,
        audioData: Data,
        model: String,
        language: String
    ) -> Data {
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append(contentsOf: "--\(boundary)\r\n".utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
            body.append(contentsOf: "\(value)\r\n".utf8)
        }

        // Audio file
        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(contentsOf: "Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".utf8)
        body.append(contentsOf: "Content-Type: audio/wav\r\n\r\n".utf8)
        body.append(audioData)
        body.append(contentsOf: "\r\n".utf8)

        field("model", model)
        field("language", language)
        field("response_format", "json")

        body.append(contentsOf: "--\(boundary)--\r\n".utf8)
        return body
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
           bundleID.contains("browser") || bundleID.contains("Browser") {
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

        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            cmdDown.postToPid(pid)
            Thread.sleep(forTimeInterval: 0.02)
            cmdUp.postToPid(pid)
        } else {
            cmdDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.02)
            cmdUp.post(tap: .cghidEventTap)
        }

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
