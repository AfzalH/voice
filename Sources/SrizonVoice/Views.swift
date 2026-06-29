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
                        .foregroundStyle(VoiceTheme.error)
                    Text("Recording...")
                    Spacer()
                    if model.settings.recordingMode == .pushToTalk {
                        Text("Release \(model.settings.hotKey.displayString) to stop")
                            .foregroundStyle(VoiceTheme.secondaryText)
                            .font(.caption)
                    } else {
                        Text("Press \(model.settings.hotKey.displayString) or esc to stop")
                            .foregroundStyle(VoiceTheme.secondaryText)
                            .font(.caption)
                    }
                }
            } else if model.isTranscribing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing...")
                        .foregroundStyle(VoiceTheme.secondaryText)
                }
            } else if model.isPostProcessing {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(VoiceTheme.primary)
                    Text("Post-processing...")
                        .foregroundStyle(VoiceTheme.secondaryText)
                    Spacer()
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

            Toggle("Handsfree Mode", isOn: Binding(
                get: { model.settings.recordingMode == .handsfree },
                set: { _ in model.toggleRecordingMode() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle("Post-processing", isOn: Binding(
                get: { model.settings.postProcessingEnabled },
                set: { _ in model.togglePostProcessing() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(VoiceTheme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .overlay(VoiceTheme.outlineVariant.opacity(0.8))

            Button {
                model.presentSettingsWindow()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VoiceQuietButtonStyle())

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(VoiceQuietButtonStyle())
        }
        .padding(12)
        .frame(width: 280)
        .foregroundStyle(VoiceTheme.onSurface)
        .tint(VoiceTheme.primary)
        .background(VoiceTheme.background)
    }
}

// MARK: - SettingsTab

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case transcription
    case history

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:        return "General"
        case .transcription:  return "Post-processing"
        case .history:        return "History"
        }
    }

    var icon: String {
        switch self {
        case .general:        return "gearshape"
        case .transcription:  return "wand.and.stars"
        case .history:        return "clock.arrow.circlepath"
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(VoiceTheme.raisedSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(VoiceTheme.outlineVariant.opacity(0.68), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
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
                    .foregroundStyle(VoiceTheme.secondaryText)
            }
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab: SettingsTab = .general
    @State private var apiKey: String = ""
    @State private var geminiModel: GeminiModel = .defaultValue
    @State private var hotKey = HotKey.defaultValue
    @State private var postProcessingEnabled = true
    @State private var copyToClipboard = false
    @State private var translationLanguage = LanguageOption.english
    @State private var favoriteTranslationLanguage1 = LanguageOption.english
    @State private var favoriteTranslationLanguage2 = LanguageOption.german
    @State private var customPrompts: [CustomPostProcessingPrompt] = []
    @State private var recordingMode: RecordingMode = .handsfree
    @State private var handsfreeMaxSeconds: Double = Double(UserSettings.defaultHandsfreeSeconds)

    private var allPermissionsGranted: Bool {
        model.hasMicrophonePermission && model.hasAccessibilityPermission && model.hasInputMonitoringPermission
    }

    private var permissionsGrantedCount: Int {
        (model.hasMicrophonePermission ? 1 : 0)
        + (model.hasAccessibilityPermission ? 1 : 0)
        + (model.hasInputMonitoringPermission ? 1 : 0)
    }

    private var visibleSettingsTabs: [SettingsTab] {
        allPermissionsGranted ? SettingsTab.allCases : [.general]
    }

    private var activeTab: SettingsTab {
        allPermissionsGranted ? selectedTab : .general
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VoiceTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ForEach(visibleSettingsTabs) { tab in
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
                                .fill(activeTab == tab
                                      ? VoiceTheme.primaryContainer.opacity(0.62)
                                      : Color.clear)
                        )
                        .foregroundStyle(activeTab == tab ? VoiceTheme.primary : VoiceTheme.onSurface)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                Spacer()
            }
            .frame(width: 180)
            .background(VoiceTheme.surface)

            Divider()
                .overlay(VoiceTheme.outlineVariant.opacity(0.8))

            // Content area
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch activeTab {
                        case .general:
                            generalPanel
                        case .transcription:
                            transcriptionPanel
                        case .history:
                            historyPanel
                        }
                    }
                    .padding(18)
                }

                Divider()
                    .overlay(VoiceTheme.outlineVariant.opacity(0.8))

                // Save footer
                HStack {
                    if !allPermissionsGranted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(VoiceTheme.warning)
                        Text("All permissions must be granted before you can use SrizonVoice.")
                            .font(.caption)
                            .foregroundStyle(VoiceTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if model.isValidatingKey {
                        ProgressView()
                            .controlSize(.small)
                        Text("Validating key...")
                            .font(.caption)
                            .foregroundStyle(VoiceTheme.secondaryText)
                    } else if let error = model.errorMessage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(VoiceTheme.error)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(VoiceTheme.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if allPermissionsGranted {
                        Button("Save") {
                            model.validateAndSaveAPIKey(
                                apiKey,
                                geminiModel: geminiModel,
                                hotKey: hotKey,
                                postProcessingEnabled: postProcessingEnabled,
                                copyToClipboard: copyToClipboard,
                                translationLanguage: translationLanguage,
                                favoriteTranslationLanguage1: favoriteTranslationLanguage1,
                                favoriteTranslationLanguage2: favoriteTranslationLanguage2,
                                customPostProcessingPrompts: customPrompts,
                                recordingMode: recordingMode,
                                handsfreeMaxSeconds: Int(handsfreeMaxSeconds)
                            ) { _ in }
                        }
                        .buttonStyle(VoiceQuietButtonStyle())
                        .disabled(model.isValidatingKey)
                        Button("Save & Close") {
                            model.validateAndSaveAPIKey(
                                apiKey,
                                geminiModel: geminiModel,
                                hotKey: hotKey,
                                postProcessingEnabled: postProcessingEnabled,
                                copyToClipboard: copyToClipboard,
                                translationLanguage: translationLanguage,
                                favoriteTranslationLanguage1: favoriteTranslationLanguage1,
                                favoriteTranslationLanguage2: favoriteTranslationLanguage2,
                                customPostProcessingPrompts: customPrompts,
                                recordingMode: recordingMode,
                                handsfreeMaxSeconds: Int(handsfreeMaxSeconds)
                            ) { success in
                                if success {
                                    model.dismissSettingsWindow()
                                }
                            }
                        }
                        .buttonStyle(VoicePrimaryButtonStyle())
                        .disabled(model.isValidatingKey)
                    } else {
                        Button("Grant Permissions (\(permissionsGrantedCount) of 3 given)") {
                            model.requestPermissions()
                        }
                        .buttonStyle(VoicePrimaryButtonStyle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(VoiceTheme.surface)
            }
        }
        .frame(width: 780, height: 610)
        .foregroundStyle(VoiceTheme.onSurface)
        .tint(VoiceTheme.primary)
        .background(VoiceTheme.background)
        .onAppear {
            apiKey = model.settings.apiKey
            geminiModel = model.settings.geminiModel
            hotKey = model.settings.hotKey
            postProcessingEnabled = model.settings.postProcessingEnabled
            copyToClipboard = model.settings.copyToClipboard
            translationLanguage = model.settings.translationLanguage
            favoriteTranslationLanguage1 = model.settings.favoriteTranslationLanguage1
            favoriteTranslationLanguage2 = model.settings.favoriteTranslationLanguage2
            customPrompts = model.settings.customPostProcessingPrompts
            recordingMode = model.settings.recordingMode
            handsfreeMaxSeconds = Double(UserSettings.clampHandsfreeSeconds(model.settings.handsfreeMaxSeconds))
            model.errorMessage = nil
            model.refreshPermissions()
        }
    }

    // MARK: - General Panel

    @ViewBuilder
    private var generalPanel: some View {
        permissionsCard

        if allPermissionsGranted {
            apiKeyCard
            shortcutCard
            recordingModeCard
        }
    }

    private var apiKeyCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    SettingsCardHeader(title: "API Key")
                    Spacer()
                    GeminiModelSelector(selection: $geminiModel)
                }
                SecureField("Gemini API Key", text: $apiKey)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(VoiceTheme.error, lineWidth: allPermissionsGranted && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1.5 : 0)
                    )
                    .onChange(of: apiKey) { _ in
                        model.errorMessage = nil
                    }
                Link("Get your key from aistudio.google.com", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.caption)
            }
        }
    }

    private var shortcutCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                SettingsCardHeader(title: "Shortcut", subtitle: recordingMode == .pushToTalk ? "Hold to dictate, release to insert text" : "Press to start/stop recording")
                HotKeyRecorderField(hotKey: $hotKey)
                Text("Suggested hotkeys: fn, ⌃⌥, ⌥⌘")
                    .font(.caption)
                    .foregroundStyle(VoiceTheme.secondaryText)
                if let conflict = fnKeyConflict {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(VoiceTheme.warning)
                            .font(.caption)
                        Text("The fn key is assigned to \"\(conflict)\" in System Settings and may not work as a shortcut. Choose a different key, or change the fn key assignment in **System Settings › Keyboard**.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var recordingModeCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                SettingsCardHeader(title: "Recording Mode", subtitle: "How the shortcut triggers recording")
                RecordingModeSelector(selection: $recordingMode)

                if recordingMode == .handsfree {
                    HStack(spacing: 12) {
                        Text("Auto-stop")
                            .font(.callout)
                        Text(Self.handsfreeDurationLabel(Int(handsfreeMaxSeconds)))
                            .fontWeight(.semibold)
                            .frame(width: 80, alignment: .leading)
                        Slider(
                            value: $handsfreeMaxSeconds,
                            in: Double(UserSettings.minHandsfreeSeconds)...Double(UserSettings.maxHandsfreeSeconds),
                            step: 30
                        )
                    }
                    Text("Recording stops automatically after this duration, or press the shortcut / Esc to stop early.")
                        .font(.caption)
                        .foregroundStyle(VoiceTheme.secondaryText)
                }
            }
        }
    }

    private var permissionsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                SettingsCardHeader(title: "Permissions", subtitle: allPermissionsGranted ? "Ready for API key and shortcut setup" : "Grant all permissions to continue setup")
                HStack(spacing: 16) {
                    PermissionRow(title: "Microphone", granted: model.hasMicrophonePermission)
                    PermissionRow(title: "Accessibility", granted: model.hasAccessibilityPermission)
                    PermissionRow(title: "Input Monitoring", granted: model.hasInputMonitoringPermission)
                    Spacer()
                    if !model.hasInputMonitoringPermission {
                        Button("Restart App") {
                            Self.restartApp()
                        }
                        .buttonStyle(VoiceQuietButtonStyle())
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

    private static func handsfreeDurationLabel(_ seconds: Int) -> String {
        let clampedSeconds = UserSettings.clampHandsfreeSeconds(seconds)
        if clampedSeconds < 60 {
            return "\(clampedSeconds) seconds"
        }
        let minutes = clampedSeconds / 60
        let remainingSeconds = clampedSeconds % 60
        if remainingSeconds == 0 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return "\(minutes)m \(remainingSeconds)s"
    }

    // MARK: - Transcription Panel

    @ViewBuilder
    private var transcriptionPanel: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "Post-processing", subtitle: "When off, transcripts are inserted immediately")
                Toggle("Show post-processing panel after transcription", isOn: $postProcessingEnabled)
                    .toggleStyle(.checkbox)
            }
        }

        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "Clipboard", subtitle: "Optionally keep a copy of each dictation on the clipboard")
                Toggle("Copy dictation to clipboard", isOn: $copyToClipboard)
                    .toggleStyle(.checkbox)
            }
        }

        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "Translation", subtitle: "Used by the floating post-processing panel")
                Picker("Default chooser language", selection: $translationLanguage) {
                    ForEach(LanguageOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Picker("Favorite 1", selection: $favoriteTranslationLanguage1) {
                        ForEach(LanguageOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Picker("Favorite 2", selection: $favoriteTranslationLanguage2) {
                        ForEach(LanguageOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }
            }
        }

        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SettingsCardHeader(title: "Custom Prompts", subtitle: "Shown as saved actions after transcription")
                    Spacer()
                    Button {
                        customPrompts.append(CustomPostProcessingPrompt(title: "New prompt", prompt: ""))
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(VoiceQuietButtonStyle())
                }

                if customPrompts.isEmpty {
                    Text("No custom prompts saved.")
                        .font(.caption)
                        .foregroundStyle(VoiceTheme.secondaryText)
                } else {
                    ForEach($customPrompts) { $prompt in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Prompt name", text: $prompt.title)
                                Button(role: .destructive) {
                                    deleteCustomPrompt(prompt.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(VoiceTheme.error)
                                }
                                .buttonStyle(.borderless)
                            }
                            TextEditor(text: $prompt.prompt)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 90)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(VoiceTheme.outlineVariant.opacity(0.85), lineWidth: 1)
                                )
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func deleteCustomPrompt(_ id: UUID) {
        customPrompts.removeAll { $0.id == id }
    }

    // MARK: - History Panel

    @ViewBuilder
    private var historyPanel: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    SettingsCardHeader(title: "Dictation History", subtitle: "Click an entry to copy it to the clipboard")
                    Spacer()
                    Button(role: .destructive) {
                        model.clearDictationHistory()
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                    .buttonStyle(VoiceQuietButtonStyle())
                    .disabled(model.dictationHistory.isEmpty)
                }
                Toggle("Save new dictations to history", isOn: Binding(
                    get: { model.settings.historyEnabled },
                    set: { model.setHistoryEnabled($0) }
                ))
                .toggleStyle(.checkbox)
            }
        }

        SettingsCard {
            if model.dictationHistory.isEmpty {
                Text("No dictation history yet.")
                    .font(.callout)
                    .foregroundStyle(VoiceTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.dictationHistory.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().overlay(VoiceTheme.outlineVariant.opacity(0.5))
                        }
                        HistoryRow(entry: entry) {
                            model.copyToClipboard(entry.text)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let entry: DictationHistoryEntry
    let onCopy: () -> Void
    @State private var copied = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Button {
            onCopy()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.text)
                        .font(.callout)
                        .foregroundStyle(VoiceTheme.onSurface)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.dateFormatter.string(from: entry.date))
                        .font(.caption2)
                        .foregroundStyle(VoiceTheme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.clipboard")
                    .font(.system(size: 13))
                    .foregroundStyle(copied ? VoiceTheme.success : VoiceTheme.secondaryText)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GeminiModelSelector

private struct GeminiModelSelector: View {
    @Binding var selection: GeminiModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(GeminiModel.allCases, id: \.self) { model in
                Button {
                    selection = model
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: selection == model ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selection == model ? VoiceTheme.primary : VoiceTheme.secondaryText)
                        Text(model.displayName)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selection == model ? VoiceTheme.primaryContainer.opacity(0.52) : VoiceTheme.surfaceVariant.opacity(0.32))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(selection == model ? VoiceTheme.primary.opacity(0.42) : VoiceTheme.outlineVariant.opacity(0.62), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == model ? .isSelected : [])
                .accessibilityLabel(model.displayName)
            }
        }
    }
}

// MARK: - RecordingModeSelector

private struct RecordingModeSelector: View {
    @Binding var selection: RecordingMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RecordingMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selection == mode ? "record.circle.fill" : "circle")
                            .foregroundStyle(selection == mode ? VoiceTheme.primary : VoiceTheme.secondaryText)
                        Text(mode.displayName)
                            .font(.callout.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selection == mode ? VoiceTheme.primaryContainer.opacity(0.58) : VoiceTheme.surfaceVariant.opacity(0.36))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selection == mode ? VoiceTheme.primary.opacity(0.46) : VoiceTheme.outlineVariant.opacity(0.70), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
            }
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
                .foregroundStyle(granted ? VoiceTheme.success : VoiceTheme.secondaryText)
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
