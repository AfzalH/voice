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
}

// MARK: - CaretPositionHelper

/// Returns the focused caret's position in screen coordinates, or nil if unavailable.
/// Some apps (e.g. Electron) may return invalid coordinates.
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
        // Reject obviously wrong values (e.g. Electron returning 0, screenHeight)
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
        // Use range (location, 1) to get bounds of char at caret; length 0 often fails
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
    var onReconnectState: ((Bool) -> Void)?

    private let settings: UserSettings
    private let insertionService: TextInsertionService
    private let audioCapture = AudioCaptureService()
    private let gladiaClient = GladiaRealtimeClient()
    private var isRunning = false

    /// Latest partial transcript text that hasn't been finalized yet.
    /// Accessed only on the main thread.
    private var lastPartialText: String = ""

    init(settings: UserSettings, insertionService: TextInsertionService) {
        self.settings = settings
        self.insertionService = insertionService
        bindCallbacks()
    }

    func start(languages: [String]) async throws {
        guard !isRunning else { return }
        try await gladiaClient.startSession(
            apiKey: settings.apiKey,
            languages: languages
        )
        try audioCapture.startCapture { [weak self] data in
            self?.gladiaClient.sendAudioChunk(data)
        } levelHandler: { [weak self] level in
            self?.onAudioLevel?(level)
        }
        isRunning = true
    }

    func stop() async {
        guard isRunning else { return }
        audioCapture.stopCapture()
        await gladiaClient.stopSession()

        // Insert any remaining partial transcript that was never finalized.
        await MainActor.run {
            let remaining = lastPartialText
            lastPartialText = ""
            if !remaining.isEmpty {
                #if DEBUG
                print("[Dictation] inserting remaining partial: \"\(remaining)\"")
                #endif
                let success = insertionService.insertText(remaining)
                if !success {
                    onError?("Unable to insert text in current app.")
                }
            }
        }

        isRunning = false
    }

    private func bindCallbacks() {
        gladiaClient.onReconnectState = { [weak self] reconnecting in
            self?.onReconnectState?(reconnecting)
        }
        gladiaClient.onError = { [weak self] message in
            self?.onError?(message)
        }
        gladiaClient.onTranscript = { [weak self] text, isFinal in
            // Dispatch to main thread — AX insertion, NSPasteboard, and CGEvent
            // all require the main thread for reliable operation.
            DispatchQueue.main.async {
                guard let self else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

                if isFinal {
                    // Clear partial tracker — this utterance is now finalized.
                    self.lastPartialText = ""
                    guard !trimmed.isEmpty else { return }
                    let success = self.insertionService.insertText(trimmed)
                    if !success {
                        self.onError?("Unable to insert text in current app.")
                    }
                } else {
                    // Track the latest partial so we can insert it on stop
                    // if is_final never arrives.
                    self.lastPartialText = trimmed
                }
            }
        }
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
                let normalizedLevel = min(max(rms * 6, 0.02), 1.0)
                levelHandler(normalizedLevel)

                // Skip sending silent chunks to save bandwidth.
                guard rms > self.silenceThreshold else { return }

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

// MARK: - StopWaiterTimeoutHandle

/// Sendable handle that runs resume work on a queue. Used to avoid capturing
/// non-Sendable `GladiaRealtimeClient` in `DispatchQueue.global().asyncAfter`.
private final class StopWaiterTimeoutHandle: @unchecked Sendable {
    private let queue: DispatchQueue
    private var work: (() -> Void)?

    init(queue: DispatchQueue, work: @escaping () -> Void) {
        self.queue = queue
        self.work = work
    }

    func tryResume() {
        queue.sync {
            work?()
            work = nil
        }
    }
}

// MARK: - GladiaRealtimeClient

final class GladiaRealtimeClient {
    var onTranscript: ((String, Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onReconnectState: ((Bool) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var sessionURL: URL?
    private var intentionalStop = false
    private var reconnectAttempts = 0
    private var usingBinaryFrames = true

    /// Continuation used to wait for final transcripts after sending stop_recording.
    private var stopContinuation: CheckedContinuation<Void, Never>?

    /// Serial queue protecting all mutable state.
    private let stateQueue = DispatchQueue(label: "voice.gladia.state")

    func startSession(apiKey: String, languages: [String]) async throws {
        let (_, url) = try await initializeSession(apiKey: apiKey, languages: languages)
        stateQueue.sync {
            sessionURL = url
            intentionalStop = false
            reconnectAttempts = 0
            usingBinaryFrames = true
        }
        connectWebSocket(url: url)
    }

    func stopSession() async {
        stateQueue.sync { intentionalStop = true }
        let stopPayload = URLSessionWebSocketTask.Message.string(#"{"type":"stop_recording"}"#)
        try? await webSocketTask?.send(stopPayload)

        // Wait up to 2 seconds for the server to deliver any final
        // transcripts before tearing down the socket.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stateQueue.sync { stopContinuation = continuation }
            // Timeout fallback — resume after 2s if no final transcript arrived.
            let queue = stateQueue
            // Work runs inside queue.sync, so we can access stopContinuation directly.
            let resumeWork = { [weak self] in
                guard let self else { return }
                self.stopContinuation?.resume()
                self.stopContinuation = nil
            }
            // Capture only Sendable values: queue and a closure that we invoke.
            // The closure captures self but is only run on stateQueue.
            let timeoutHandle = StopWaiterTimeoutHandle(queue: queue, work: resumeWork)
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                timeoutHandle.tryResume()
            }
        }

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        stateQueue.sync { webSocketTask = nil }
    }

    func sendAudioChunk(_ data: Data) {
        let (task, useBinary) = stateQueue.sync { (webSocketTask, usingBinaryFrames) }
        guard let task else { return }
        if useBinary {
            task.send(.data(data)) { [weak self] error in
                if error != nil {
                    self?.stateQueue.sync { self?.usingBinaryFrames = false }
                    self?.sendAudioChunkAsJSON(data)
                }
            }
        } else {
            sendAudioChunkAsJSON(data)
        }
    }

    /// Validates an API key by starting a session and immediately closing it.
    static func validateAPIKey(_ apiKey: String) async -> Bool {
        guard let url = URL(string: "https://api.gladia.io/v2/live") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-gladia-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "solaria-1",
            "encoding": "wav/pcm",
            "sample_rate": 16_000,
            "bit_depth": 16,
            "channels": 1,
            "language_config": ["languages": ["en"], "code_switching": false],
            "messages_config": ["receive_partial_transcripts": false],
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = bodyData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 401 || http.statusCode == 403 { return false }
            guard (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let wsURLString = json["url"] as? String,
                  let wsURL = URL(string: wsURLString)
            else { return false }
            // Immediately tear down the validation session.
            let ws = URLSession.shared.webSocketTask(with: wsURL)
            ws.resume()
            let stop = URLSessionWebSocketTask.Message.string(#"{"type":"stop_recording"}"#)
            try? await ws.send(stop)
            ws.cancel(with: .normalClosure, reason: nil)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func sendAudioChunkAsJSON(_ data: Data) {
        let task = stateQueue.sync { webSocketTask }
        guard let task else { return }
        let base64 = data.base64EncodedString()
        let payload = #"{"type":"audio_chunk","data":{"chunk":"\#(base64)"}}"#
        task.send(.string(payload)) { [weak self] error in
            if let error {
                self?.onError?("Audio send failed: \(error.localizedDescription)")
            }
        }
    }

    private func connectWebSocket(url: URL) {
        stateQueue.sync {
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            let task = session.webSocketTask(with: url)
            webSocketTask = task
            task.resume()
        }
        receiveLoop()
    }

    private func receiveLoop() {
        let task = stateQueue.sync { webSocketTask }
        guard let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveLoop()
            case .failure(let error):
                self.handleDisconnect(error: error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String?
        switch message {
        case .string(let value): text = value
        case .data(let data): text = String(data: data, encoding: .utf8)
        @unknown default: text = nil
        }
        guard let text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }

        if type == "transcript",
           let transcriptData = json["data"] as? [String: Any]
        {
            // Default to true — when receive_partial_transcripts is false,
            // Gladia may omit is_final since all messages are implicitly final.
            let isFinal = transcriptData["is_final"] as? Bool ?? true
            let utterance = transcriptData["utterance"] as? [String: Any]
            let transcriptText = (utterance?["text"] as? String) ?? ""
            #if DEBUG
            print("[Gladia] transcript is_final=\(isFinal) text=\"\(transcriptText)\"")
            #endif
            onTranscript?(transcriptText, isFinal)

            // If this was the final transcript, unblock stopSession's wait.
            if isFinal {
                resolveStopWaiter()
            }
        } else if type == "error" {
            let message = (json["message"] as? String) ?? "Gladia returned an error."
            onError?(message)
        } else {
            #if DEBUG
            print("[Gladia] message type=\"\(type)\" data=\(json)")
            #endif
        }
    }

    private func handleDisconnect(error: Error?) {
        let stopped = stateQueue.sync { intentionalStop }
        if stopped {
            resolveStopWaiter()
            return
        }
        Task { await reconnect() }
    }

    /// Resumes the stop-wait continuation if one is pending.
    private func resolveStopWaiter() {
        stateQueue.sync {
            stopContinuation?.resume()
            stopContinuation = nil
        }
    }

    private func reconnect() async {
        let url = stateQueue.sync { sessionURL }
        guard let url else { return }
        onReconnectState?(true)
        while true {
            let (attempts, stopped) = stateQueue.sync { (reconnectAttempts, intentionalStop) }
            guard attempts < 3 && !stopped else { break }
            stateQueue.sync { reconnectAttempts += 1 }
            connectWebSocket(url: url)
            // Give the WebSocket time to handshake before probing.
            let currentAttempt = stateQueue.sync { reconnectAttempts }
            try? await Task.sleep(nanoseconds: UInt64(currentAttempt) * 1_000_000_000)
            if await pingSocket() {
                stateQueue.sync { reconnectAttempts = 0 }
                onReconnectState?(false)
                return
            }
        }
        onReconnectState?(false)
        onError?("Connection lost. Please start dictation again.")
    }

    private func pingSocket() async -> Bool {
        let task = stateQueue.sync { webSocketTask }
        guard let task else { return false }
        return await withCheckedContinuation { continuation in
            task.sendPing { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private func initializeSession(apiKey: String, languages: [String]) async throws -> (String, URL) {
        guard let url = URL(string: "https://api.gladia.io/v2/live") else {
            throw DictationError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-gladia-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "solaria-1",
            "encoding": "wav/pcm",
            "sample_rate": 16_000,
            "bit_depth": 16,
            "channels": 1,
            "language_config": [
                "languages": languages,
                "code_switching": languages.count > 1,
            ],
            "messages_config": [
                "receive_partial_transcripts": true,
                "receive_final_transcripts": true,
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DictationError.invalidResponse
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw DictationError.invalidAPIKey
        }
        guard (200...299).contains(httpResponse.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let urlString = json["url"] as? String,
              let wsURL = URL(string: urlString)
        else {
            throw DictationError.sessionInitializationFailed
        }
        return (id, wsURL)
    }
}

// MARK: - TextInsertionService

final class TextInsertionService {
    func insertText(_ text: String) -> Bool {
        // For Notes and Pages, prefer clipboard paste immediately as it's more reliable
        if let appName = NSWorkspace.shared.frontmostApplication?.localizedName,
           (appName.contains("Notes") || appName.contains("Pages")) {
            return pasteWithClipboardFallback(text)
        }
        
        if insertWithAccessibility(text) {
            return true
        }
        return pasteWithClipboardFallback(text)
    }

    /// Uses Accessibility API with hierarchy traversal for Notes, Pages, and other
    /// apps that expose text editing via child elements rather than the focused element.
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

        // Try focused element first (works for most apps like Chrome, Word, Obsidian)
        if trySetText(on: element, text: text) {
            return true
        }

        // Notes, Pages, and some Apple apps focus a container; the actual text
        // field is often a descendant. Search children recursively.
        if trySetTextInDescendants(of: element, text: text) {
            return true
        }

        // Some single-line fields use kAXValueAttribute instead of kAXSelectedText
        if trySetValue(on: element, text: text) {
            return true
        }

        return false
    }

    private func trySetText(on element: AXUIElement, text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    private func trySetValue(on element: AXUIElement, text: String) -> Bool {
        // kAXValueAttribute is used by NSTextField and some single-line editors
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    private func trySetTextInDescendants(of element: AXUIElement, text: String, depth: Int = 0) -> Bool {
        guard depth < 5 else { return false } // Limit recursion
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef,
              let array = (children as? [AXUIElement])
        else { return false }
        for child in array {
            if trySetText(on: child, text: text) || trySetValue(on: child, text: text) {
                return true
            }
            if trySetTextInDescendants(of: child, text: text, depth: depth + 1) {
                return true
            }
        }
        return false
    }

    private func pasteWithClipboardFallback(_ text: String) -> Bool {
        guard let savedClipboard = ClipboardSnapshot.capture() else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        Thread.sleep(forTimeInterval: 0.05)

        // Use kVK_ANSI_V for layout-independent V key; set timestamps for macOS 15+ compatibility
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let timestamp = UInt64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))

        guard let cmdDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return false }
        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand
        cmdDown.timestamp = CGEventTimestamp(timestamp)
        cmdUp.timestamp = CGEventTimestamp(timestamp + 1)

        // Post to frontmost app's PID for better delivery in Notes, Pages, etc.
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            cmdDown.postToPid(pid)
            // Small delay between keydown and keyup
            Thread.sleep(forTimeInterval: 0.02)
            cmdUp.postToPid(pid)
        } else {
            cmdDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.02)
            cmdUp.post(tap: .cghidEventTap)
        }

        // Longer delay for clipboard restoration to ensure paste completes
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
