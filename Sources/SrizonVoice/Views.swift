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
                    Text("Release \(model.settings.hotKey.displayString) to stop")
                        .foregroundStyle(.secondary)
                        .font(.caption)
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
                    Text("Hold \(model.settings.hotKey.displayString) to dictate")
                    Spacer()
                }
            }

            Picker("Primary Language", selection: Binding(
                get: { model.settings.language },
                set: { model.switchLanguage($0) }
            )) {
                ForEach(LanguageOption.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            
            Picker("Secondary Language", selection: Binding(
                get: { model.settings.secondaryLanguage },
                set: { model.switchSecondaryLanguage($0) }
            )) {
                Text("None").tag(nil as LanguageOption?)
                ForEach(LanguageOption.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language as LanguageOption?)
                }
            }

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

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var apiKey: String = ""
    @State private var hotKey = HotKey.defaultValue
    @State private var language = LanguageOption.english
    @State private var secondaryLanguage: LanguageOption?
    @State private var transcriptionModel = TranscriptionModel.whisperTurbo

    /// Returns the name of the system feature the fn key is assigned to, or nil if unassigned.
    /// macOS stores this in com.apple.HIToolbox under AppleFnUsageType:
    ///   0 = Do Nothing, 1 = Change Input Source, 2 = Show Emoji & Symbols, 3 = Start Dictation
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
        Form {
            Section("API Key") {
                SecureField("Groq API Key", text: $apiKey)
                    .onChange(of: apiKey) { _ in
                        model.errorMessage = nil
                    }
                Link("Get your key from console.groq.com", destination: URL(string: "https://console.groq.com/keys")!)
            }

            Section("Shortcut") {
                HotKeyRecorderField(hotKey: $hotKey)
                Text("Hold this shortcut anywhere you want to type, speak, then release to insert transcribed text. Suggested hotkeys: fn, ⌃⌥, ⌥⌘")
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

            Section("Model & Language") {
                Picker("Model", selection: $transcriptionModel) {
                    ForEach(TranscriptionModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.radioGroup)
                Picker("Primary Language", selection: $language) {
                    ForEach(LanguageOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                
                Picker("Secondary Language (Optional)", selection: $secondaryLanguage) {
                    Text("None").tag(nil as LanguageOption?)
                    ForEach(LanguageOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option as LanguageOption?)
                    }
                }
            }

            Section("Permissions") {
                PermissionRow(title: "Microphone", granted: model.hasMicrophonePermission)
                PermissionRow(title: "Accessibility", granted: model.hasAccessibilityPermission)
                PermissionRow(title: "Input Monitoring", granted: model.hasInputMonitoringPermission)
                Button("Grant Permissions") {
                    model.requestPermissions()
                }
            }

            HStack {
                if model.isValidatingKey {
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
                Button("Save") {
                    model.validateAndSaveAPIKey(
                        apiKey,
                        hotKey: hotKey,
                        language: language,
                        secondaryLanguage: secondaryLanguage,
                        transcriptionModel: transcriptionModel
                    ) { success in
                        if success {
                            model.dismissSettingsWindow()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isValidatingKey)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            apiKey = model.settings.apiKey
            hotKey = model.settings.hotKey
            language = model.settings.language
            secondaryLanguage = model.settings.secondaryLanguage
            transcriptionModel = model.settings.transcriptionModel
            model.errorMessage = nil
            model.requestPermissions()
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
