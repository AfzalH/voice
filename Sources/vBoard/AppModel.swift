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
    @Published private(set) var dictationHistory: [DictationHistoryEntry] = []
    /// Languages most recently chosen (spoken hint or translation target), newest first.
    @Published private(set) var recentLanguages: [LanguageOption] = []
    /// How the in-progress recording was started; `nil` when idle.
    @Published private(set) var activeRecordingMode: RecordingMode?

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
    /// Delays the recording island + sound for push-to-talk until the press has
    /// outlived the tap threshold, so fn taps and combos stay silent.
    private var pushToTalkFeedbackTask: Task<Void, Never>?
    private var recordingFeedbackShown = false
    private var pendingInsertionTarget: TextInsertionTarget?
    /// True while `startDictation` is in its async startup (before recording begins).
    private var isStartingDictation = false
    /// Set when a stop is requested before async startup finishes, so the in-flight
    /// start can abort instead of leaving recording stuck on after the key is released.
    private var stopRequestedDuringStart = false

    init() {
        settings.load()
        dictationHistory = DictationHistoryStore.load()
        recentLanguages = RecentLanguagesStore.load()
        ensureLaunchAtLogin()
        refreshPermissions()
        configureCallbacks()
        // Only register the hotkey if we already have permissions.
        // On first launch the user hasn't granted Input Monitoring yet and
        // calling CGEvent.tapCreate / CGPreflightListenEventAccess can
        // trigger the system dialog before the user is ready.
        if hasAccessibilityPermission {
            registerHotKey()
        }
        bindStopControls()
    }

    // MARK: - Public

    func registerHotKey() {
        hotKeyMonitor.unregister()
        // Keyboard event taps are allowed once the app is Accessibility-trusted;
        // a separate Input Monitoring grant is normally not needed.
        guard permissionManager.accessibilityPermissionGranted else {
            return
        }
        escapeKeyMonitor.start()
        do {
            try hotKeyMonitor.register(
                pushToTalk: settings.pushToTalkHotKey,
                handsfree: settings.handsfreeHotKey
            )
            needsInputMonitoringFallback = false
        } catch {
            // Some systems still refuse the tap without Input Monitoring; surface
            // that permission as an optional extra step instead of failing silently.
            needsInputMonitoringFallback = !permissionManager.inputMonitoringPermissionGranted
            if !needsInputMonitoringFallback {
                showError("Failed to register global shortcut. Try restarting the app.")
            }
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

    // MARK: - Languages

    /// Languages offered as quick picks in the menu popover.
    var quickPickLanguages: [LanguageOption] {
        RecentLanguagesStore.quickPicks(from: recentLanguages, count: 4)
    }

    /// Sets the language hint sent with each transcription. `nil` = auto-detect.
    func setSpokenLanguage(_ language: LanguageOption?) {
        objectWillChange.send()
        settings.spokenLanguage = language
        if let language { noteLanguageUsed(language) }
        saveSettings()
    }

    /// Records a language as recently used so it surfaces in quick pickers.
    func noteLanguageUsed(_ language: LanguageOption) {
        recentLanguages = RecentLanguagesStore.bump(language, in: recentLanguages)
        RecentLanguagesStore.save(recentLanguages)
    }

    func togglePostProcessing() {
        objectWillChange.send()
        settings.postProcessingEnabled.toggle()
        saveSettings()
    }

    // MARK: - Dictation History

    func setHistoryEnabled(_ enabled: Bool) {
        objectWillChange.send()
        settings.historyEnabled = enabled
        saveSettings()
    }

    /// Saves a generated dictation to history (newest first), when enabled.
    private func recordDictation(_ text: String) {
        guard settings.historyEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entries = dictationHistory
        entries.insert(DictationHistoryEntry(text: trimmed), at: 0)
        if entries.count > DictationHistoryStore.maxEntries {
            entries = Array(entries.prefix(DictationHistoryStore.maxEntries))
        }
        dictationHistory = entries
        DictationHistoryStore.save(entries)
    }

    func clearDictationHistory() {
        dictationHistory = []
        DictationHistoryStore.save([])
    }

    /// Copies a history entry to the clipboard (used when a row is clicked).
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @Published var hasMicrophonePermission = false
    @Published var hasAccessibilityPermission = false
    @Published var hasInputMonitoringPermission = false
    /// True when creating the keyboard event tap failed even though Accessibility is
    /// granted. Only then is Input Monitoring shown as an additional permission.
    @Published var needsInputMonitoringFallback = false

    /// Everything the app needs to work: Microphone + Accessibility, plus Input
    /// Monitoring only on systems where the event tap could not be created without it.
    var hasRequiredPermissions: Bool {
        hasMicrophonePermission && hasAccessibilityPermission
            && (!needsInputMonitoringFallback || hasInputMonitoringPermission)
    }

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

            // Accessibility is what allows the keyboard event tap; register now.
            registerHotKey()

            // Step 3 (rare): Input Monitoring, only if the tap could not be created.
            if needsInputMonitoringFallback, !permissionManager.inputMonitoringPermissionGranted {
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
        pushToTalkHotKey: HotKey?,
        handsfreeHotKey: HotKey?,
        postProcessingEnabled: Bool = true,
        copyToClipboard: Bool = false,
        translationLanguage: LanguageOption = .english,
        favoriteTranslationLanguage1: LanguageOption = .english,
        favoriteTranslationLanguage2: LanguageOption = .german,
        customPostProcessingPrompts: [CustomPostProcessingPrompt] = [],
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
            settings.pushToTalkHotKey = pushToTalkHotKey
            settings.handsfreeHotKey = handsfreeHotKey
            settings.postProcessingEnabled = postProcessingEnabled
            settings.copyToClipboard = copyToClipboard
            settings.translationLanguage = translationLanguage
            settings.favoriteTranslationLanguage1 = favoriteTranslationLanguage1
            settings.favoriteTranslationLanguage2 = favoriteTranslationLanguage2
            settings.customPostProcessingPrompts = UserSettings.normalizedCustomPostProcessingPrompts(customPostProcessingPrompts)
            settings.handsfreeMaxSeconds = UserSettings.clampHandsfreeSeconds(handsfreeMaxSeconds)
            saveSettings()
            errorMessage = nil
            completion(true)
        }
    }

    // MARK: - Private

    private func startDictation(mode: RecordingMode) {
        guard !isStartingDictation else { return }
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

        isStartingDictation = true
        stopRequestedDuringStart = false
        Task {
            defer { isStartingDictation = false }
            let micGranted = await permissionManager.requestMicrophonePermission()
            guard micGranted else {
                showError("Microphone permission is required.")
                stopRequestedDuringStart = false
                pendingInsertionTarget = nil
                return
            }
            // A stop (key-up / Esc) may have arrived while we were still starting up.
            // Honor it here instead of leaving recording stuck on after the key released.
            guard !stopRequestedDuringStart else {
                stopRequestedDuringStart = false
                pendingInsertionTarget = nil
                return
            }
            do {
                try dictationCoordinator.startRecording()
                isDictating = true
                activeRecordingMode = mode
                recordingFeedbackShown = false
                if mode == .pushToTalk {
                    // Stay silent until the press is clearly a hold, not a tap.
                    pushToTalkFeedbackTask?.cancel()
                    pushToTalkFeedbackTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(GlobalHotKeyMonitor.tapThreshold * 1_000_000_000))
                        guard let self, !Task.isCancelled, self.isDictating else { return }
                        self.showRecordingFeedback()
                    }
                } else {
                    showRecordingFeedback()
                }
            } catch {
                isDictating = false
                activeRecordingMode = nil
                showError(error.localizedDescription)
                recordingIslandController.hide()
            }
        }
    }

    private func showRecordingFeedback() {
        guard !recordingFeedbackShown else { return }
        recordingFeedbackShown = true
        recordingIslandController.show()
        NSSound(named: "Tink")?.play()
    }

    /// Discards the current recording without transcribing. Silent when no
    /// feedback was shown yet (tap or combination on the push-to-talk key).
    private func cancelActiveRecording() {
        pushToTalkFeedbackTask?.cancel()
        pushToTalkFeedbackTask = nil
        cancelHandsfreeAutoStop()
        guard isDictating else {
            if isStartingDictation { stopRequestedDuringStart = true }
            return
        }
        dictationCoordinator.cancelRecording()
        isDictating = false
        activeRecordingMode = nil
        pendingInsertionTarget = nil
        recordingIslandController.hide()
        if recordingFeedbackShown { NSSound(named: "Pop")?.play() }
        recordingFeedbackShown = false
    }

    private func stopDictation() {
        guard isDictating else {
            // The key was released (or Esc pressed) before async startup finished.
            // Remember it so the pending start aborts instead of getting stuck on.
            if isStartingDictation { stopRequestedDuringStart = true }
            return
        }
        cancelHandsfreeAutoStop()
        pushToTalkFeedbackTask?.cancel()
        pushToTalkFeedbackTask = nil
        recordingFeedbackShown = false
        isDictating = false
        activeRecordingMode = nil
        isTranscribing = true
        recordingIslandController.showTranscribing()
        NSSound(named: "Pop")?.play()

        Task {
            let target = pendingInsertionTarget ?? insertionService.captureCurrentTarget()
            let targetAppName = target?.appName ?? "Unknown App"
            let transcript = await dictationCoordinator.stopRecordingAndTranscribe(
                targetAppName: targetAppName,
                spokenLanguage: settings.spokenLanguage
            )
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
                self?.activeRecordingMode = nil
                self?.isTranscribing = false
                self?.isPostProcessing = false
                self?.recordingIslandController.hide()
            }
        }

        hotKeyMonitor.onPushToTalkBegan = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isPostProcessing, !self.isDictating, !self.isTranscribing else { return }
                self.startDictation(mode: .pushToTalk)
            }
        }
        hotKeyMonitor.onPushToTalkEnded = { [weak self] cancelled in
            Task { @MainActor in
                guard let self, self.activeRecordingMode == .pushToTalk || self.isStartingDictation else { return }
                if cancelled {
                    self.cancelActiveRecording()
                } else {
                    self.stopDictation()
                }
            }
        }
        hotKeyMonitor.onHandsfreeToggled = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isPostProcessing else { return }
                if self.isDictating {
                    // Also lets the handsfree key finish a push-to-talk hold.
                    self.stopDictation()
                } else if !self.isTranscribing {
                    self.startDictation(mode: .handsfree)
                    self.startHandsfreeAutoStop()
                }
            }
        }
    }

    private func bindStopControls() {
        escapeKeyMonitor.onEscapePressed = { [weak self] in
            Task { @MainActor in
                guard let self, self.isDictating else { return }
                if self.activeRecordingMode == .handsfree {
                    // In handsfree mode, Escape stops and transcribes
                    self.stopDictation()
                } else {
                    // In push-to-talk mode, Escape cancels without transcribing
                    self.cancelActiveRecording()
                }
            }
        }
        // The tap itself is started in registerHotKey(), once Accessibility is
        // granted. Opening a keyboard tap before that makes macOS prompt for
        // Input Monitoring, which the app does not otherwise need.
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
        // Quick translation buttons: recently used languages first, then favorites.
        var favoriteLanguages = recentLanguages
        for favorite in [settings.favoriteTranslationLanguage1, settings.favoriteTranslationLanguage2]
            where !favoriteLanguages.contains(favorite)
        {
            favoriteLanguages.append(favorite)
        }
        favoriteLanguages = Array(favoriteLanguages.prefix(4))
        let customPrompts = settings.customPostProcessingPrompts
        let selectedModel = settings.geminiModel
        let processor = postProcessingClient

        postProcessingPanelController.show(
            transcript: trimmed,
            anchorPoint: target?.caretScreenPoint,
            translationLanguage: initialLanguage,
            favoriteTranslationLanguages: favoriteLanguages,
            customPrompts: customPrompts,
            processAction: { [weak self] sourceText, action in
                if case .translate(let language) = action {
                    await MainActor.run { self?.noteLanguageUsed(language) }
                }
                return try await processor.process(
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

        recordDictation(trimmed)
        insertionService.insertText(trimmed, into: target, copyToClipboard: settings.copyToClipboard)
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
                if self.hasRequiredPermissions {
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
