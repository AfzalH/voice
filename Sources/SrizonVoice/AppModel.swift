import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var isDictating = false
    @Published var isTranscribing = false
    @Published var isPostProcessing = false
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String?
    @Published var isValidatingKey = false

    let settings = UserSettings()
    private let insertionService = TextInsertionService()
    private let postProcessingClient = GeminiPostProcessingClient()
    private let recordingIslandController = RecordingIslandController()
    private let postProcessingPanelController = PostProcessingPanelController()
    private lazy var dictationCoordinator = DictationCoordinator(
        settings: settings,
        insertionService: insertionService
    )
    private lazy var hotKeyMonitor = GlobalHotKeyMonitor()
    private let escapeKeyMonitor = GlobalEscapeKeyMonitor()
    private let permissionManager = PermissionManager()
    private lazy var settingsWindowManager = SettingsWindowManager(model: self)
    private var errorDismissTask: Task<Void, Never>?
    private var permissionPollTask: Task<Void, Never>?
    private var handsfreeAutoStopTask: Task<Void, Never>?
    private var pendingInsertionTarget: TextInsertionTarget?

    init() {
        settings.load()
        ensureLaunchAtLogin()
        refreshPermissions()
        configureCallbacks()
        // Only register the hotkey if we already have permissions.
        // On first launch the user hasn't granted Input Monitoring yet and
        // calling CGEvent.tapCreate / CGPreflightListenEventAccess can
        // trigger the system dialog before the user is ready.
        if hasInputMonitoringPermission {
            registerHotKey()
        }
        bindStopControls()
    }

    // MARK: - Public

    func registerHotKey() {
        hotKeyMonitor.unregister()
        guard permissionManager.inputMonitoringPermissionGranted else {
            // Don't attempt to create event tap without Input Monitoring permission —
            // CGEvent.tapCreate will silently return nil.
            return
        }
        do {
            try hotKeyMonitor.register(hotKey: settings.hotKey)
        } catch {
            showError("Failed to register global shortcut. Check Input Monitoring permission in System Settings > Privacy & Security.")
        }
    }

    func saveSettings() {
        objectWillChange.send()
        settings.save()
        registerHotKey()
    }

    func presentSettingsIfNeeded() {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            presentSettingsWindow()
        }
    }

    func presentSettingsWindow() {
        settingsWindowManager.show()
        startPermissionPolling()
    }

    func dismissSettingsWindow() {
        settingsWindowManager.hide()
    }

    /// Called by SettingsWindowManager when the window closes (via Save or close button).
    func onSettingsWindowClosed() {
        stopPermissionPolling()
    }

    func switchOutputMode(_ outputMode: TranscriptionOutputMode) {
        objectWillChange.send()
        settings.outputMode = outputMode
        saveSettings()
    }

    func switchTranslationLanguage(_ language: LanguageOption) {
        objectWillChange.send()
        settings.translationLanguage = language
        saveSettings()
    }

    func toggleRecordingMode() {
        objectWillChange.send()
        settings.recordingMode = settings.recordingMode == .pushToTalk ? .handsfree : .pushToTalk
        saveSettings()
    }

    func togglePostProcessing() {
        objectWillChange.send()
        settings.postProcessingEnabled.toggle()
        saveSettings()
    }

    @Published var hasMicrophonePermission = false
    @Published var hasAccessibilityPermission = false
    @Published var hasInputMonitoringPermission = false

    func requestPermissions() {
        Task { @MainActor in
            // Step 1: Microphone — system shows its own dialog
            if !permissionManager.microphonePermissionGranted {
                _ = await permissionManager.requestMicrophonePermission()
                refreshPermissions()
                // Small delay so the mic dialog fully dismisses before the next one
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            // Step 2: Accessibility — wait until granted before moving on
            if !permissionManager.accessibilityPermissionGranted {
                _ = permissionManager.requestAccessibilityPermission(prompt: true)
                // Poll until the user grants accessibility
                while !permissionManager.accessibilityPermissionGranted {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                }
                refreshPermissions()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            // Step 3: Input Monitoring — only prompt after accessibility is granted
            if !permissionManager.inputMonitoringPermissionGranted {
                // Deactivate so the system dialog appears in front of the settings window
                NSApp.deactivate()
                try? await Task.sleep(nanoseconds: 200_000_000)
                permissionManager.requestInputMonitoringPermission()
                refreshPermissions()
            }
        }
    }

    /// Validates the key against the Gemini API, then saves all settings on success.
    func validateAndSaveAPIKey(
        _ key: String,
        geminiModel: GeminiModel = .defaultValue,
        hotKey: HotKey,
        postProcessingEnabled: Bool = true,
        translationLanguage: LanguageOption = .english,
        favoriteTranslationLanguage1: LanguageOption = .english,
        favoriteTranslationLanguage2: LanguageOption = .german,
        customPostProcessingPrompts: [CustomPostProcessingPrompt] = [],
        recordingMode: RecordingMode = .handsfree,
        handsfreeMaxSeconds: Int = UserSettings.defaultHandsfreeSeconds,
        completion: @escaping (Bool) -> Void
    ) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError("Gemini API key cannot be empty.", autoDismiss: false)
            completion(false)
            return
        }

        isValidatingKey = true
        Task {
            let geminiValid = await GeminiTranscriptionClient.validateAPIKey(trimmed)
            guard geminiValid else {
                isValidatingKey = false
                showError("Invalid Gemini API key. Please check and try again.", autoDismiss: false)
                completion(false)
                return
            }

            isValidatingKey = false
            settings.apiKey = trimmed
            settings.geminiModel = geminiModel
            settings.hotKey = hotKey
            settings.postProcessingEnabled = postProcessingEnabled
            settings.translationLanguage = translationLanguage
            settings.favoriteTranslationLanguage1 = favoriteTranslationLanguage1
            settings.favoriteTranslationLanguage2 = favoriteTranslationLanguage2
            settings.customPostProcessingPrompts = UserSettings.normalizedCustomPostProcessingPrompts(customPostProcessingPrompts)
            settings.recordingMode = recordingMode
            settings.handsfreeMaxSeconds = UserSettings.clampHandsfreeSeconds(handsfreeMaxSeconds)
            saveSettings()
            errorMessage = nil
            completion(true)
        }
    }

    // MARK: - Private

    private func startDictation() {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showError("Add your Gemini API key in Settings.")
            return
        }
        refreshPermissions()
        guard hasAccessibilityPermission else {
            showError("Accessibility permission is required for text insertion.")
            requestPermissions()
            return
        }
        pendingInsertionTarget = insertionService.captureCurrentTarget()

        Task {
            let micGranted = await permissionManager.requestMicrophonePermission()
            guard micGranted else {
                showError("Microphone permission is required.")
                return
            }
            do {
                try dictationCoordinator.startRecording()
                isDictating = true
                recordingIslandController.show()
                NSSound(named: "Tink")?.play()
            } catch {
                isDictating = false
                showError(error.localizedDescription)
                recordingIslandController.hide()
            }
        }
    }

    private func stopDictation() {
        guard isDictating else { return }
        cancelHandsfreeAutoStop()
        isDictating = false
        isTranscribing = true
        recordingIslandController.showTranscribing()
        NSSound(named: "Pop")?.play()

        Task {
            let target = pendingInsertionTarget ?? insertionService.captureCurrentTarget()
            let targetAppName = target?.appName ?? "Unknown App"
            let transcript = await dictationCoordinator.stopRecordingAndTranscribe(targetAppName: targetAppName)
            isTranscribing = false
            recordingIslandController.hide()
            guard let transcript else {
                pendingInsertionTarget = nil
                return
            }
            guard settings.postProcessingEnabled else {
                completePostProcessing(with: transcript, target: target)
                return
            }
            presentPostProcessingPanel(transcript: transcript, target: target)
        }
    }

    private func showError(_ message: String, autoDismiss: Bool = true) {
        errorMessage = message
        errorDismissTask?.cancel()
        guard autoDismiss else { return }
        errorDismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            errorMessage = nil
        }
    }

    private func configureCallbacks() {
        dictationCoordinator.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
                self?.recordingIslandController.updateLevel(level)
            }
        }
        dictationCoordinator.onTranscribing = { [weak self] transcribing in
            Task { @MainActor in
                self?.isTranscribing = transcribing
                if transcribing {
                    self?.recordingIslandController.showTranscribing()
                }
            }
        }
        dictationCoordinator.onError = { [weak self] message in
            Task { @MainActor in
                self?.showError(message)
                self?.isDictating = false
                self?.isTranscribing = false
                self?.isPostProcessing = false
                self?.recordingIslandController.hide()
            }
        }

        hotKeyMonitor.onKeyDown = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isPostProcessing else { return }
                if self.settings.recordingMode == .pushToTalk {
                    // Push-to-talk: press starts
                    guard !self.isDictating, !self.isTranscribing else { return }
                    self.startDictation()
                } else {
                    // Handsfree: toggle on/off
                    if self.isDictating {
                        self.stopDictation()
                    } else if !self.isTranscribing {
                        self.startDictation()
                        self.startHandsfreeAutoStop()
                    }
                }
            }
        }
        hotKeyMonitor.onKeyUp = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isPostProcessing else { return }
                if self.settings.recordingMode == .pushToTalk {
                    self.stopDictation()
                }
                // Handsfree: ignore key up
            }
        }
    }

    private func bindStopControls() {
        escapeKeyMonitor.onEscapePressed = { [weak self] in
            Task { @MainActor in
                guard let self, self.isDictating else { return }
                if self.settings.recordingMode == .handsfree {
                    // In handsfree mode, Escape stops and transcribes
                    self.cancelHandsfreeAutoStop()
                    self.stopDictation()
                } else {
                    // In push-to-talk mode, Escape cancels without transcribing
                    self.dictationCoordinator.cancelRecording()
                    self.isDictating = false
                    self.recordingIslandController.hide()
                    NSSound(named: "Pop")?.play()
                }
            }
        }
        escapeKeyMonitor.start()
    }

    private func startHandsfreeAutoStop() {
        cancelHandsfreeAutoStop()
        let maxSeconds = UInt64(UserSettings.clampHandsfreeSeconds(settings.handsfreeMaxSeconds))
        handsfreeAutoStopTask = Task {
            try? await Task.sleep(nanoseconds: maxSeconds * 1_000_000_000)
            guard !Task.isCancelled, self.isDictating else { return }
            self.stopDictation()
        }
    }

    private func cancelHandsfreeAutoStop() {
        handsfreeAutoStopTask?.cancel()
        handsfreeAutoStopTask = nil
    }

    private func presentPostProcessingPanel(transcript: String, target: TextInsertionTarget?) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pendingInsertionTarget = nil
            return
        }

        isPostProcessing = true
        let targetAppName = target?.appName ?? "the target app"
        let apiKey = settings.apiKey
        let initialLanguage = settings.translationLanguage
        let favoriteLanguages = [
            settings.favoriteTranslationLanguage1,
            settings.favoriteTranslationLanguage2,
        ]
        let customPrompts = settings.customPostProcessingPrompts
        let selectedModel = settings.geminiModel
        let processor = postProcessingClient

        postProcessingPanelController.show(
            transcript: trimmed,
            anchorPoint: target?.caretScreenPoint,
            translationLanguage: initialLanguage,
            favoriteTranslationLanguages: favoriteLanguages,
            customPrompts: customPrompts,
            processAction: { sourceText, action in
                try await processor.process(
                    apiKey: apiKey,
                    model: selectedModel,
                    transcript: sourceText,
                    action: action,
                    targetAppName: targetAppName
                )
            },
            insertText: { [weak self] finalText in
                Task { @MainActor in
                    self?.completePostProcessing(with: finalText, target: target)
                }
            },
            savePrompt: { [weak self] title, prompt in
                guard let self else { return [] }
                return self.saveCustomPostProcessingPrompt(title: title, prompt: prompt)
            },
            onClosed: { [weak self] in
                Task { @MainActor in
                    self?.isPostProcessing = false
                    self?.pendingInsertionTarget = nil
                }
            }
        )
    }

    private func completePostProcessing(with text: String, target: TextInsertionTarget?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError("Post-processing returned empty text.")
            return
        }

        postProcessingPanelController.hide()
        isPostProcessing = false
        pendingInsertionTarget = nil

        let success = insertionService.insertText(trimmed, into: target, copyToClipboard: true)
        if !success {
            showError("Text copied to clipboard, but could not be inserted in the target app.")
        }
    }

    private func saveCustomPostProcessingPrompt(title: String, prompt: String) -> [CustomPostProcessingPrompt] {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else {
            return settings.customPostProcessingPrompts
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = cleanPrompt.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "Custom prompt"
        let promptTitle = cleanTitle.isEmpty ? String(fallbackTitle.prefix(36)) : cleanTitle
        settings.customPostProcessingPrompts.append(
            CustomPostProcessingPrompt(title: promptTitle, prompt: cleanPrompt)
        )
        settings.customPostProcessingPrompts = UserSettings.normalizedCustomPostProcessingPrompts(settings.customPostProcessingPrompts)
        saveSettings()
        objectWillChange.send()
        return settings.customPostProcessingPrompts
    }

    func refreshPermissions() {
        hasMicrophonePermission = permissionManager.microphonePermissionGranted
        hasAccessibilityPermission = permissionManager.accessibilityPermissionGranted
        hasInputMonitoringPermission = permissionManager.inputMonitoringPermissionGranted
    }

    private func startPermissionPolling() {
        stopPermissionPolling()
        permissionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let hadAccessibility = self.hasAccessibilityPermission
                let hadInputMonitoring = self.hasInputMonitoringPermission
                self.refreshPermissions()
                // Re-register hotkeys when Accessibility or Input Monitoring is newly granted.
                // CGEvent taps created before permission was granted silently fail,
                // so we must recreate them once the permission is available.
                if (!hadAccessibility && self.hasAccessibilityPermission) ||
                   (!hadInputMonitoring && self.hasInputMonitoringPermission) {
                    self.registerHotKey()
                }
                if self.hasMicrophonePermission && self.hasAccessibilityPermission && self.hasInputMonitoringPermission {
                    return
                }
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = nil
    }

    private func ensureLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                // Non-fatal in development builds.
            }
        }
    }
}
