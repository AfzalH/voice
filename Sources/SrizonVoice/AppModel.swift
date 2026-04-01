import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var isDictating = false
    @Published var isTranscribing = false
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String?
    @Published var isValidatingKey = false

    let settings = UserSettings()
    private let insertionService = TextInsertionService()
    private let recordingIslandController = RecordingIslandController()
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

    func switchLanguage(_ language: LanguageOption) {
        objectWillChange.send()
        // Track the old language in recents
        let oldLanguage = settings.language
        if oldLanguage != language {
            var recents = settings.recentLanguages.filter { $0 != language && $0 != oldLanguage }
            recents.insert(oldLanguage, at: 0)
            settings.recentLanguages = Array(recents.prefix(3))
        }
        settings.language = language
        saveSettings()
    }

    func togglePostProcessing() {
        objectWillChange.send()
        settings.postProcessingEnabled.toggle()
        saveSettings()
    }

    func toggleRecordingMode() {
        objectWillChange.send()
        settings.recordingMode = settings.recordingMode == .pushToTalk ? .handsfree : .pushToTalk
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

    /// Validates the key against the Groq API (and Gemini if enabled), then saves all settings on success.
    func validateAndSaveAPIKey(
        _ key: String,
        hotKey: HotKey,
        language: LanguageOption? = nil,
        transcriptionModel: TranscriptionModel = .whisperTurbo,
        postProcessingEnabled: Bool = true,
        postProcessingModel: PostProcessingModel = .gptOss120b,
        postProcessingSystemPrompt: String = "",
        useGemini: Bool = false,
        geminiApiKey: String = "",
        recordingMode: RecordingMode = .pushToTalk,
        handsfreeMaxMinutes: Int = 5,
        completion: @escaping (Bool) -> Void
    ) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError("API key cannot be empty.", autoDismiss: false)
            completion(false)
            return
        }

        // Validate Gemini API key if Gemini post-processing is enabled
        let trimmedGeminiKey = geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if postProcessingEnabled && useGemini && trimmedGeminiKey.isEmpty {
            showError("Gemini API key cannot be empty when Gemini post-processing is enabled.", autoDismiss: false)
            completion(false)
            return
        }

        isValidatingKey = true
        Task {
            let groqValid = await GroqTranscriptionClient.validateAPIKey(trimmed)
            guard groqValid else {
                isValidatingKey = false
                showError("Invalid Groq API key. Please check and try again.", autoDismiss: false)
                completion(false)
                return
            }

            // Validate Gemini key if enabled
            if postProcessingEnabled && useGemini {
                let geminiValid = await LLMClient.validateGeminiAPIKey(trimmedGeminiKey)
                guard geminiValid else {
                    isValidatingKey = false
                    showError("Invalid Gemini API key. Please check and try again.", autoDismiss: false)
                    completion(false)
                    return
                }
            }

            isValidatingKey = false
            settings.apiKey = trimmed
            settings.hotKey = hotKey
            settings.transcriptionModel = transcriptionModel
            if let language { settings.language = language }
            settings.postProcessingEnabled = postProcessingEnabled
            settings.postProcessingModel = postProcessingModel
            settings.postProcessingSystemPrompt = postProcessingSystemPrompt.isEmpty
                ? UserSettings.defaultSystemPrompt
                : postProcessingSystemPrompt
            settings.useGemini = useGemini
            settings.geminiApiKey = trimmedGeminiKey
            settings.recordingMode = recordingMode
            settings.handsfreeMaxMinutes = max(1, handsfreeMaxMinutes)
            saveSettings()
            errorMessage = nil
            completion(true)
        }
    }

    // MARK: - Private

    private func startDictation() {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showError("Add your Groq API key in Settings.")
            return
        }
        refreshPermissions()
        guard hasAccessibilityPermission else {
            showError("Accessibility permission is required for text insertion.")
            requestPermissions()
            return
        }

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
            await dictationCoordinator.stopRecordingAndTranscribe()
            isTranscribing = false
            recordingIslandController.hide()
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
                self?.recordingIslandController.hide()
            }
        }

        hotKeyMonitor.onKeyDown = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
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
        let maxSeconds = UInt64(settings.handsfreeMaxMinutes) * 60
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
