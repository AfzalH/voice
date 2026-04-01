import AppKit
import SwiftUI

// MARK: - MenuBarContentView

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isDictating {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.red)
                    Text("Recording...")
                    Spacer()
                    if model.settings.recordingMode == .pushToTalk {
                        Text("Release \(model.settings.hotKey.displayString) to stop")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Text("Press \(model.settings.hotKey.displayString) or esc to stop")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            } else if model.isTranscribing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing...")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    if model.settings.recordingMode == .pushToTalk {
                        Text("Hold \(model.settings.hotKey.displayString) to dictate")
                    } else {
                        Text("Press \(model.settings.hotKey.displayString) to dictate")
                    }
                    Spacer()
                }
            }

            Picker("Language", selection: Binding(
                get: { model.settings.language },
                set: { model.switchLanguage($0) }
            )) {
                ForEach(LanguageOption.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }

            if !model.settings.recentLanguages.isEmpty {
                HStack(spacing: 6) {
                    Text("Recent:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.settings.recentLanguages.filter { $0 != model.settings.language }, id: \.self) { lang in
                        Button(action: { model.switchLanguage(lang) }) {
                            Text(lang.displayName)
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Toggle("Post-Processing", isOn: Binding(
                get: { model.settings.postProcessingEnabled },
                set: { _ in model.togglePostProcessing() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle("Handsfree Mode", isOn: Binding(
                get: { model.settings.recordingMode == .handsfree },
                set: { _ in model.toggleRecordingMode() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Settings") {
                model.presentSettingsWindow()
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

// MARK: - SettingsTab

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case transcription
    case postProcessing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:        return "General"
        case .transcription:  return "Transcription"
        case .postProcessing: return "Post-Processing"
        }
    }

    var icon: String {
        switch self {
        case .general:        return "gearshape"
        case .transcription:  return "waveform"
        case .postProcessing: return "sparkles"
        }
    }
}

// MARK: - SettingsCard

private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}

// MARK: - SettingsCardHeader

private struct SettingsCardHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab: SettingsTab = .general
    @State private var apiKey: String = ""
    @State private var hotKey = HotKey.defaultValue
    @State private var language = LanguageOption.english
    @State private var transcriptionModel = TranscriptionModel.whisperTurbo
    @State private var postProcessingEnabled: Bool = true
    @State private var postProcessingModel: PostProcessingModel = .gptOss120b
    @State private var postProcessingSystemPrompt: String = ""
    @State private var useGemini: Bool = false
    @State private var geminiApiKey: String = ""
    @State private var recordingMode: RecordingMode = .pushToTalk
    @State private var handsfreeMaxMinutes: Int = 5

    private var allPermissionsGranted: Bool {
        model.hasMicrophonePermission && model.hasAccessibilityPermission && model.hasInputMonitoringPermission
    }

    private var permissionsGrantedCount: Int {
        (model.hasMicrophonePermission ? 1 : 0)
        + (model.hasAccessibilityPermission ? 1 : 0)
        + (model.hasInputMonitoringPermission ? 1 : 0)
    }

    private var fnKeyConflict: String? {
        guard hotKey.isFnKey else { return nil }
        let type = UserDefaults(suiteName: "com.apple.HIToolbox")?.integer(forKey: "AppleFnUsageType") ?? 0
        switch type {
        case 0:  return nil
        case 1:  return "Change Input Source"
        case 2:  return "Show Emoji & Symbols"
        case 3:  return "Start Dictation"
        default: return "a system function"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 4) {
                Text("SETTINGS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ForEach(SettingsTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .frame(width: 18)
                            Text(tab.label)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == tab
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.clear)
                        )
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                Spacer()
            }
            .frame(width: 180)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content area
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case .general:
                            generalPanel
                        case .transcription:
                            transcriptionPanel
                        case .postProcessing:
                            postProcessingPanel
                        }
                    }
                    .padding(24)
                }

                Divider()

                // Save footer
                HStack {
                    if !allPermissionsGranted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("All permissions must be granted before you can use SrizonVoice.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if model.isValidatingKey {
                        ProgressView()
                            .controlSize(.small)
                        Text("Validating key...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let error = model.errorMessage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if allPermissionsGranted {
                        Button("Save") {
                            model.validateAndSaveAPIKey(
                                apiKey,
                                hotKey: hotKey,
                                language: language,
                                transcriptionModel: transcriptionModel,
                                postProcessingEnabled: postProcessingEnabled,
                                postProcessingModel: postProcessingModel,
                                postProcessingSystemPrompt: postProcessingSystemPrompt,
                                useGemini: useGemini,
                                geminiApiKey: geminiApiKey,
                                recordingMode: recordingMode,
                                handsfreeMaxMinutes: handsfreeMaxMinutes
                            ) { _ in }
                        }
                        .disabled(model.isValidatingKey)
                        Button("Save & Close") {
                            model.validateAndSaveAPIKey(
                                apiKey,
                                hotKey: hotKey,
                                language: language,
                                transcriptionModel: transcriptionModel,
                                postProcessingEnabled: postProcessingEnabled,
                                postProcessingModel: postProcessingModel,
                                postProcessingSystemPrompt: postProcessingSystemPrompt,
                                useGemini: useGemini,
                                geminiApiKey: geminiApiKey,
                                recordingMode: recordingMode,
                                handsfreeMaxMinutes: handsfreeMaxMinutes
                            ) { success in
                                if success {
                                    model.dismissSettingsWindow()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isValidatingKey)
                    } else {
                        Button("Grant Permissions (\(permissionsGrantedCount) of 3 given)") {
                            model.requestPermissions()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 750, height: 550)
        .onAppear {
            apiKey = model.settings.apiKey
            hotKey = model.settings.hotKey
            language = model.settings.language
            transcriptionModel = model.settings.transcriptionModel
            postProcessingEnabled = model.settings.postProcessingEnabled
            postProcessingModel = model.settings.postProcessingModel
            postProcessingSystemPrompt = model.settings.postProcessingSystemPrompt.isEmpty
                ? UserSettings.defaultSystemPrompt
                : model.settings.postProcessingSystemPrompt
            useGemini = model.settings.useGemini
            geminiApiKey = model.settings.geminiApiKey
            recordingMode = model.settings.recordingMode
            handsfreeMaxMinutes = model.settings.handsfreeMaxMinutes
            model.errorMessage = nil
            model.refreshPermissions()
        }
    }

    // MARK: - General Panel

    @ViewBuilder
    private var generalPanel: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "API Key", subtitle: "Your Groq API key for transcription")
                SecureField("Groq API Key", text: $apiKey)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.red, lineWidth: allPermissionsGranted && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1.5 : 0)
                    )
                    .onChange(of: apiKey) { _ in
                        model.errorMessage = nil
                    }
                Link("Get your key from console.groq.com", destination: URL(string: "https://console.groq.com/keys")!)
                    .font(.caption)
            }
        }

        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "Shortcut", subtitle: recordingMode == .pushToTalk ? "Hold to dictate, release to insert text" : "Press to start/stop recording")
                HotKeyRecorderField(hotKey: $hotKey)
                Text("Suggested hotkeys: fn, ⌃⌥, ⌥⌘")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let conflict = fnKeyConflict {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text("The fn key is assigned to \"\(conflict)\" in System Settings and may not work as a shortcut. Choose a different key, or change the fn key assignment in **System Settings › Keyboard**.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
        }

        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "Recording Mode", subtitle: "How the shortcut triggers recording")
                Picker("Mode", selection: $recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if recordingMode == .handsfree {
                    HStack {
                        Text("Auto-stop after")
                        TextField("", value: $handsfreeMaxMinutes, format: .number)
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                        Text("minutes")
                    }
                    .font(.callout)
                    Text("Recording stops automatically after this duration, or press the shortcut / Esc to stop early.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "Permissions", subtitle: allPermissionsGranted ? nil : "All permissions are required to use SrizonVoice")
                PermissionRow(title: "Microphone", granted: model.hasMicrophonePermission)
                PermissionRow(title: "Accessibility", granted: model.hasAccessibilityPermission)
                HStack {
                    PermissionRow(
                        title: model.hasInputMonitoringPermission
                            ? "Input Monitoring"
                            : "Input Monitoring (restart app to detect changes)",
                        granted: model.hasInputMonitoringPermission
                    )
                    if !model.hasInputMonitoringPermission {
                        Spacer()
                        Button("Restart App") {
                            Self.restartApp()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Transcription Panel

    @ViewBuilder
    private var transcriptionPanel: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "Model", subtitle: "Choose the transcription model")
                Picker("Model", selection: $transcriptionModel) {
                    ForEach(TranscriptionModel.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
        }

        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "Language", subtitle: "Select your dictation language")
                Picker("Language", selection: $language) {
                    ForEach(LanguageOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            }
        }
    }

    // MARK: - Post-Processing Panel

    @ViewBuilder
    private var postProcessingPanel: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "Post-Processing", subtitle: "Run transcriptions through an LLM")
                Toggle("Enable Post-Processing", isOn: $postProcessingEnabled)

                if postProcessingEnabled {
                    Toggle("Use Gemini instead of Groq for post-processing", isOn: $useGemini)
                }
            }
        }

        if postProcessingEnabled {
            if useGemini {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsCardHeader(title: "Gemini API Key", subtitle: "Required for Gemini post-processing (model: gemini-3.1-flash-lite-preview)")
                        SecureField("Gemini API Key", text: $geminiApiKey)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.red, lineWidth: geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1.5 : 0)
                            )
                        Link("Get your key from aistudio.google.com", destination: URL(string: "https://aistudio.google.com/apikey")!)
                            .font(.caption)
                    }
                }
                .transition(.opacity)
            } else {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsCardHeader(title: "Model", subtitle: "LLM model for post-processing")
                        Picker("Model", selection: $postProcessingModel) {
                            ForEach(PostProcessingModel.allCases, id: \.self) { m in
                                Text(m.displayName).tag(m)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                }
                .transition(.opacity)
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsCardHeader(title: "System Prompt", subtitle: "Instructions for the LLM")
                    TextEditor(text: $postProcessingSystemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .transition(.opacity)
        }
    }
}

// MARK: - PermissionRow

struct PermissionRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(title)
        }
    }
}

// MARK: - HotKeyRecorderField

struct HotKeyRecorderField: NSViewRepresentable {
    @Binding var hotKey: HotKey

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: hotKey.displayString,
            target: context.coordinator,
            action: #selector(Coordinator.startRecording)
        )
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = hotKey.displayString
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hotKey: $hotKey)
    }

    final class Coordinator: NSObject {
        @Binding private var hotKey: HotKey
        private var monitor: Any?
        private weak var button: NSButton?
        /// Tracks the peak set of modifiers held during this recording session.
        private var peakModifiers: NSEvent.ModifierFlags = []

        init(hotKey: Binding<HotKey>) {
            _hotKey = hotKey
        }

        @objc func startRecording(_ sender: NSButton) {
            button = sender
            sender.title = "Press new shortcut..."
            peakModifiers = []
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self else { return event }

                if event.type == .flagsChanged {
                    // Detect the fn/Globe key
                    if event.keyCode == 63, event.modifierFlags.contains(.function) {
                        self.hotKey = HotKey(keyCode: 63, modifiers: 0, isFnKey: true)
                        self.finish()
                        return nil
                    }

                    let currentMods = event.modifierFlags.intersection([.command, .shift, .option, .control])
                    let currentCount = self.modifierCount(currentMods)
                    let peakCount = self.modifierCount(self.peakModifiers)

                    if currentCount >= peakCount {
                        // Modifiers being added or same
                        self.peakModifiers = currentMods
                    } else if peakCount >= 2 {
                        // A modifier was released and we had 2+ — record as modifier-only
                        self.hotKey = HotKey(
                            keyCode: 0,
                            modifiers: KeyCodeMap.carbonModifiers(from: self.peakModifiers),
                            isModifierOnly: true
                        )
                        self.finish()
                        return nil
                    } else {
                        self.peakModifiers = currentMods
                    }
                    return event
                }

                // Regular key + modifier combination
                guard event.type == .keyDown else { return event }
                let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                guard !modifiers.isEmpty else { return nil }
                self.hotKey = HotKey(
                    keyCode: UInt32(event.keyCode),
                    modifiers: KeyCodeMap.carbonModifiers(from: modifiers)
                )
                self.finish()
                return nil
            }
        }

        private func finish() {
            button?.title = hotKey.displayString
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            peakModifiers = []
        }

        private func modifierCount(_ flags: NSEvent.ModifierFlags) -> Int {
            var count = 0
            if flags.contains(.command) { count += 1 }
            if flags.contains(.shift) { count += 1 }
            if flags.contains(.option) { count += 1 }
            if flags.contains(.control) { count += 1 }
            return count
        }
    }
}
