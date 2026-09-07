import AppKit
import SwiftUI

// MARK: - MenuBarContentView

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    private var pushToTalk: HotKey? { model.settings.pushToTalkHotKey }
    private var handsfree: HotKey? { model.settings.handsfreeHotKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow

            languageRow

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
        .frame(width: 300)
        .foregroundStyle(VoiceTheme.onSurface)
        .tint(VoiceTheme.primary)
        .background(VoiceTheme.background)
    }

    @ViewBuilder
    private var statusRow: some View {
        if model.isDictating {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundStyle(VoiceTheme.error)
                Text("Recording...")
                Spacer()
                Group {
                    if model.activeRecordingMode == .pushToTalk, let pushToTalk {
                        Text("Release \(pushToTalk.displayString) to insert")
                    } else if let handsfree {
                        Text("Press \(handsfree.displayString) or esc to stop")
                    } else {
                        Text("Press esc to stop")
                    }
                }
                .foregroundStyle(VoiceTheme.secondaryText)
                .font(.caption)
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
            VStack(alignment: .leading, spacing: 3) {
                if let pushToTalk {
                    shortcutHint(pushToTalk, action: "Hold to dictate")
                }
                if let handsfree {
                    shortcutHint(handsfree, action: "Tap for handsfree")
                }
                if pushToTalk == nil && handsfree == nil {
                    Text("No shortcut set. Add one in Settings.")
                        .foregroundStyle(VoiceTheme.warning)
                }
            }
        }
    }

    private func shortcutHint(_ hotKey: HotKey, action: String) -> some View {
        HStack(spacing: 6) {
            Text(hotKey.displayString)
                .font(.caption.weight(.semibold).monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(VoiceTheme.surfaceVariant.opacity(0.6))
                )
            Text(action)
                .font(.callout)
            Spacer()
        }
    }

    /// Quick picker for the language the user is speaking. Shows recents (or
    /// common/system languages when there is no history yet) plus "Auto".
    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Speaking")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VoiceTheme.secondaryText)
                Spacer()
                Menu {
                    Button("Automatic") { model.setSpokenLanguage(nil) }
                    Divider()
                    ForEach(LanguageOption.allCases, id: \.self) { language in
                        Button(language.displayName) { model.setSpokenLanguage(language) }
                    }
                } label: {
                    Label("More", systemImage: "globe")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            HStack(spacing: 6) {
                LanguageChip(title: "Auto", isSelected: model.settings.spokenLanguage == nil) {
                    model.setSpokenLanguage(nil)
                }
                ForEach(chipLanguages, id: \.self) { language in
                    LanguageChip(
                        title: "\(language.flag) \(language.shortCode)",
                        isSelected: model.settings.spokenLanguage == language,
                        help: language.plainName
                    ) {
                        model.setSpokenLanguage(language)
                    }
                }
            }
        }
    }

    /// Quick picks, guaranteeing the currently selected language is visible.
    private var chipLanguages: [LanguageOption] {
        var picks = model.quickPickLanguages
        if let selected = model.settings.spokenLanguage, !picks.contains(selected) {
            picks.insert(selected, at: 0)
            picks = Array(picks.prefix(4))
        }
        return picks
    }
}

// MARK: - LanguageChip

private struct LanguageChip: View {
    let title: String
    let isSelected: Bool
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? VoiceTheme.primaryContainer.opacity(0.62) : VoiceTheme.surfaceVariant.opacity(0.36))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? VoiceTheme.primary.opacity(0.5) : VoiceTheme.outlineVariant.opacity(0.7), lineWidth: 1)
                )
                .foregroundStyle(isSelected ? VoiceTheme.primary : VoiceTheme.onSurface)
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    @State private var pushToTalkHotKey: HotKey? = HotKey.defaultPushToTalk
    @State private var handsfreeHotKey: HotKey? = HotKey.defaultHandsfree
    @State private var postProcessingEnabled = true
    @State private var copyToClipboard = false
    @State private var translationLanguage = LanguageOption.english
    @State private var favoriteTranslationLanguage1 = LanguageOption.english
    @State private var favoriteTranslationLanguage2 = LanguageOption.german
    @State private var customPrompts: [CustomPostProcessingPrompt] = []
    @State private var handsfreeMaxSeconds: Double = Double(UserSettings.defaultHandsfreeSeconds)

    private var allPermissionsGranted: Bool { model.hasRequiredPermissions }

    private var permissionsTotalCount: Int { model.needsInputMonitoringFallback ? 3 : 2 }

    private var permissionsGrantedCount: Int {
        (model.hasMicrophonePermission ? 1 : 0)
        + (model.hasAccessibilityPermission ? 1 : 0)
        + (model.needsInputMonitoringFallback && model.hasInputMonitoringPermission ? 1 : 0)
    }

    private var visibleSettingsTabs: [SettingsTab] {
        allPermissionsGranted ? SettingsTab.allCases : [.general]
    }

    private var activeTab: SettingsTab {
        allPermissionsGranted ? selectedTab : .general
    }

    private var usesFnKey: Bool {
        pushToTalkHotKey?.isFnKey == true || handsfreeHotKey?.isFnKey == true
    }

    /// Both shortcuts would fire on the same key press.
    private var shortcutsConflict: Bool {
        guard let pushToTalkHotKey, let handsfreeHotKey else { return false }
        return pushToTalkHotKey.conflicts(with: handsfreeHotKey)
    }

    private var fnKeyConflict: String? {
        guard usesFnKey else { return nil }
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
                                pushToTalkHotKey: pushToTalkHotKey,
                                handsfreeHotKey: handsfreeHotKey,
                                postProcessingEnabled: postProcessingEnabled,
                                copyToClipboard: copyToClipboard,
                                translationLanguage: translationLanguage,
                                favoriteTranslationLanguage1: favoriteTranslationLanguage1,
                                favoriteTranslationLanguage2: favoriteTranslationLanguage2,
                                customPostProcessingPrompts: customPrompts,
                                handsfreeMaxSeconds: Int(handsfreeMaxSeconds)
                            ) { _ in }
                        }
                        .buttonStyle(VoiceQuietButtonStyle())
                        .disabled(model.isValidatingKey || shortcutsConflict)
                        Button("Save & Close") {
                            model.validateAndSaveAPIKey(
                                apiKey,
                                geminiModel: geminiModel,
                                pushToTalkHotKey: pushToTalkHotKey,
                                handsfreeHotKey: handsfreeHotKey,
                                postProcessingEnabled: postProcessingEnabled,
                                copyToClipboard: copyToClipboard,
                                translationLanguage: translationLanguage,
                                favoriteTranslationLanguage1: favoriteTranslationLanguage1,
                                favoriteTranslationLanguage2: favoriteTranslationLanguage2,
                                customPostProcessingPrompts: customPrompts,
                                handsfreeMaxSeconds: Int(handsfreeMaxSeconds)
                            ) { success in
                                if success {
                                    model.dismissSettingsWindow()
                                }
                            }
                        }
                        .buttonStyle(VoicePrimaryButtonStyle())
                        .disabled(model.isValidatingKey || shortcutsConflict)
                    } else {
                        Button("Grant Permissions (\(permissionsGrantedCount) of \(permissionsTotalCount) given)") {
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
            pushToTalkHotKey = model.settings.pushToTalkHotKey
            handsfreeHotKey = model.settings.handsfreeHotKey
            postProcessingEnabled = model.settings.postProcessingEnabled
            copyToClipboard = model.settings.copyToClipboard
            translationLanguage = model.settings.translationLanguage
            favoriteTranslationLanguage1 = model.settings.favoriteTranslationLanguage1
            favoriteTranslationLanguage2 = model.settings.favoriteTranslationLanguage2
            customPrompts = model.settings.customPostProcessingPrompts
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
            VStack(alignment: .leading, spacing: 12) {
                SettingsCardHeader(title: "Shortcuts", subtitle: "Both shortcuts are active at the same time. Click a field and press a key combination; press ⌫ to disable one, ⎋ to keep the current value.")

                shortcutRow(
                    title: "Push to talk",
                    detail: "Hold to record, release to insert. A quick tap or a combination with another key is ignored, so the key keeps working normally.",
                    hotKey: $pushToTalkHotKey
                )

                Divider().overlay(VoiceTheme.outlineVariant.opacity(0.5))

                shortcutRow(
                    title: "Handsfree",
                    detail: "Tap to start recording, tap again or press Esc to stop and insert.",
                    hotKey: $handsfreeHotKey
                )

                if handsfreeHotKey != nil {
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
                    Text("Handsfree recording stops automatically after this duration.")
                        .font(.caption)
                        .foregroundStyle(VoiceTheme.secondaryText)
                }

                Text("Tips: left and right modifier keys are distinct, so “Right ⌘” alone works as a shortcut. Suggested: fn, Right ⌘, Right ⌥, ⌃⌥, ⌥Space.")
                    .font(.caption)
                    .foregroundStyle(VoiceTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if shortcutsConflict {
                    warningRow("Push to talk and Handsfree use the same shortcut. Change one of them before saving.", isError: true)
                }
                if let conflict = fnKeyConflict {
                    warningRow("The fn key is assigned to \"\(conflict)\" in System Settings. Holding fn for push to talk still works, but a single tap will trigger that system function. To avoid it, set the fn key to \"Do Nothing\" in **System Settings › Keyboard**.")
                }
            }
        }
    }

    private func shortcutRow(title: String, detail: String, hotKey: Binding<HotKey?>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(VoiceTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HotKeyRecorderField(hotKey: hotKey)
                .frame(width: 150)
        }
    }

    private func warningRow(_ text: String, isError: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(isError ? VoiceTheme.error : VoiceTheme.warning)
                .font(.caption)
            Text(.init(text))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private var permissionsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                SettingsCardHeader(title: "Permissions", subtitle: allPermissionsGranted ? "Ready for API key and shortcut setup" : "Grant all permissions to continue setup")
                HStack(spacing: 16) {
                    PermissionRow(title: "Microphone", granted: model.hasMicrophonePermission)
                    PermissionRow(title: "Accessibility", granted: model.hasAccessibilityPermission)
                    if model.needsInputMonitoringFallback {
                        PermissionRow(title: "Input Monitoring", granted: model.hasInputMonitoringPermission)
                    }
                    Spacer()
                    if !allPermissionsGranted {
                        Button("Restart App") {
                            Self.restartApp()
                        }
                        .buttonStyle(VoiceQuietButtonStyle())
                        .controlSize(.small)
                    }
                }
                if model.needsInputMonitoringFallback {
                    Text("Your system did not allow the keyboard shortcut listener with Accessibility alone. Please also grant Input Monitoring.")
                        .font(.caption)
                        .foregroundStyle(VoiceTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
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

/// Click-to-record shortcut field. Records:
///  - fn/Globe
///  - modifier-only chords, side-aware (e.g. Right ⌘, Left ⌃ + Left ⌥) — recorded
///    when the modifiers are released without any other key having been pressed
///  - a regular key with modifiers (⌥Space, either side) or a function key alone (F5)
/// Delete/Backspace clears the shortcut (disabled); Escape keeps the previous value.
struct HotKeyRecorderField: NSViewRepresentable {
    @Binding var hotKey: HotKey?

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: Self.title(for: hotKey),
            target: context.coordinator,
            action: #selector(Coordinator.startRecording)
        )
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.hotKey = $hotKey
        if !context.coordinator.isRecording {
            nsView.title = Self.title(for: hotKey)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hotKey: $hotKey)
    }

    static func title(for hotKey: HotKey?) -> String {
        hotKey?.displayString ?? "Not set"
    }

    final class Coordinator: NSObject {
        var hotKey: Binding<HotKey?>
        private var monitor: Any?
        private weak var button: NSButton?
        private(set) var isRecording = false
        /// Modifier keys currently held, tracked by key code so sides are distinct.
        private var heldModifiers: Set<ModifierKey> = []
        /// Largest chord held during this session (what a modifier-only release records).
        private var peakModifiers: Set<ModifierKey> = []

        init(hotKey: Binding<HotKey?>) {
            self.hotKey = hotKey
        }

        @objc func startRecording(_ sender: NSButton) {
            if isRecording { return }
            button = sender
            isRecording = true
            sender.title = "Press shortcut…"
            heldModifiers = []
            peakModifiers = []
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            }
        }

        /// Returns true when the event was consumed.
        private func handle(_ event: NSEvent) -> Bool {
            if event.type == .flagsChanged {
                // fn/Globe key
                if event.keyCode == 63 {
                    if event.modifierFlags.contains(.function) {
                        commit(HotKey.fnKey)
                    }
                    return true
                }

                guard let key = ModifierKey(rawValue: UInt32(event.keyCode)) else { return true }
                let familyHeld = event.modifierFlags.contains(Self.nsFlag(for: key))
                // The event's key code tells us which physical key changed; the
                // generic flag tells us whether that family is now held at all.
                if familyHeld, !heldModifiers.contains(key) {
                    heldModifiers.insert(key)
                } else if heldModifiers.contains(key) {
                    heldModifiers.remove(key)
                } else if !familyHeld {
                    heldModifiers = heldModifiers.filter { $0.cgFlag != key.cgFlag }
                }

                if heldModifiers.count >= peakModifiers.count {
                    peakModifiers = heldModifiers
                } else if heldModifiers.isEmpty || heldModifiers.count < peakModifiers.count {
                    // Released after building a chord without any regular key → modifier-only
                    commit(HotKey(
                        keyCode: 0,
                        modifiers: peakModifiers.reduce(0) { $0 | $1.carbonMask },
                        isModifierOnly: true,
                        modifierKeys: Array(peakModifiers)
                    ))
                }
                return true
            }

            guard event.type == .keyDown else { return false }

            switch event.keyCode {
            case 53: // Escape — keep current value
                finish()
                return true
            case 51, 117: // Delete / Forward delete — disable
                commit(nil)
                return true
            default:
                break
            }

            let generic = KeyCodeMap.carbonModifiers(from: event.modifierFlags)
            let isFunctionKey = Self.standaloneKeyCodes.contains(UInt32(event.keyCode))
            guard generic != 0 || isFunctionKey else {
                // A bare letter/number would hijack typing — ignore it.
                return true
            }
            // Key+modifier combos match either side (like most macOS shortcuts);
            // only modifier-only shortcuts are side-specific.
            commit(HotKey(keyCode: UInt32(event.keyCode), modifiers: generic))
            return true
        }

        private func commit(_ value: HotKey?) {
            hotKey.wrappedValue = value
            finish()
        }

        private func finish() {
            isRecording = false
            button?.title = HotKeyRecorderField.title(for: hotKey.wrappedValue)
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            heldModifiers = []
            peakModifiers = []
        }

        /// Keys that are safe as a shortcut without any modifier (function keys).
        private static let standaloneKeyCodes: Set<UInt32> = [
            96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113, 118, 120, 122,
        ]

        private static func nsFlag(for key: ModifierKey) -> NSEvent.ModifierFlags {
            switch key.cgFlag {
            case .maskCommand: return .command
            case .maskShift:   return .shift
            case .maskAlternate: return .option
            default:           return .control
            }
        }
    }
}
