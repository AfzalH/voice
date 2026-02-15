import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var isDictating = false
    @Published var audioLevel: Float = 0
    @Published var errorMessage: String?
    @Published var isReconnecting = false
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

    init() {
        settings.load()
        ensureLaunchAtLogin()
        refreshPermissions()
        configureCallbacks()
        registerHotKey()
        bindStopControls()
    }

    // MARK: - Public

    func registerHotKey() {
        hotKeyMonitor.unregister()
        do {
            try hotKeyMonitor.register(hotKey: settings.hotKey) { [weak self] in
                Task { @MainActor in
                    self?.toggleDictation()
                }
            }
        } catch {
            showError("Failed to register global shortcut.")
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
        stopPermissionPolling()
    }

    func switchLanguage(_ language: LanguageOption) {
        let wasDictating = isDictating
        if wasDictating {
            stopDictation()
        }
        // Notify SwiftUI that the model will change so the menu updates
        objectWillChange.send()
        settings.language = language
        saveSettings()
        if wasDictating {
            startDictation()
        }
    }
    
    func switchSecondaryLanguage(_ language: LanguageOption?) {
        let wasDictating = isDictating
        if wasDictating {
            stopDictation()
        }
        objectWillChange.send()
        settings.secondaryLanguage = language
        saveSettings()
        if wasDictating {
            startDictation()
        }
    }

    func toggleDictation() {
        isDictating ? stopDictation() : startDictation()
    }

    @Published var hasMicrophonePermission = false
    @Published var hasAccessibilityPermission = false

    func requestPermissions() {
        Task {
            _ = await permissionManager.requestMicrophonePermission()
            _ = permissionManager.requestAccessibilityPermission(prompt: true)
            refreshPermissions()
        }
    }

    /// Validates the key against the Gladia API, then saves all settings on success.
    func validateAndSaveAPIKey(
        _ key: String,
        hotKey: HotKey,
        language: LanguageOption? = nil,
        secondaryLanguage: LanguageOption? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError("API key cannot be empty.", autoDismiss: false)
            completion(false)
            return
        }
        isValidatingKey = true
        Task {
            let valid = await GladiaRealtimeClient.validateAPIKey(trimmed)
            isValidatingKey = false
            if valid {
                settings.apiKey = trimmed
                settings.hotKey = hotKey
                if let language { settings.language = language }
                settings.secondaryLanguage = secondaryLanguage
                saveSettings()
                errorMessage = nil
                completion(true)
            } else {
                showError("Invalid API key. Please check and try again.", autoDismiss: false)
                completion(false)
            }
        }
    }

    // MARK: - Private

    private func startDictation() {
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showError("Add your Gladia API key in Settings.")
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
                let languages = [settings.language.code] + (settings.secondaryLanguage.map { [$0.code] } ?? [])
                try await dictationCoordinator.start(languages: languages)
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
        Task {
            await dictationCoordinator.stop()
            isDictating = false
            recordingIslandController.hide()
            NSSound(named: "Pop")?.play()
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
        dictationCoordinator.onReconnectState = { [weak self] reconnecting in
            Task { @MainActor in
                self?.isReconnecting = reconnecting
            }
        }
        dictationCoordinator.onError = { [weak self] message in
            Task { @MainActor in
                self?.showError(message)
                self?.isDictating = false
                self?.recordingIslandController.hide()
            }
        }
    }

    private func bindStopControls() {
        recordingIslandController.onStopTapped = { [weak self] in
            Task { @MainActor in
                self?.stopDictation()
            }
        }
        escapeKeyMonitor.onEscapePressed = { [weak self] in
            Task { @MainActor in
                guard let self, self.isDictating else { return }
                self.stopDictation()
            }
        }
        escapeKeyMonitor.start()
    }

    private func refreshPermissions() {
        hasMicrophonePermission = permissionManager.microphonePermissionGranted
        hasAccessibilityPermission = permissionManager.accessibilityPermissionGranted
    }

    private func startPermissionPolling() {
        stopPermissionPolling()
        permissionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.refreshPermissions()
                if self.hasMicrophonePermission && self.hasAccessibilityPermission {
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
