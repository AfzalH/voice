import AppKit
import SwiftUI

// MARK: - MenuBarContentView

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.toggleDictation()
            } label: {
                HStack {
                    Text(model.isDictating ? "Stop Dictation" : "Start Dictation")
                    Spacer()
                    Text(model.settings.hotKey.displayString)
                        .foregroundStyle(.secondary)
                        .font(.caption)
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

            if model.isReconnecting {
                Text("Reconnecting...")
                    .font(.caption)
                    .foregroundStyle(.orange)
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

    var body: some View {
        Form {
            Section("API Key") {
                SecureField("Gladia API Key", text: $apiKey)
                    .onChange(of: apiKey) { _ in
                        model.errorMessage = nil
                    }
                Link("Get your key from app.gladia.io", destination: URL(string: "https://app.gladia.io")!)
            }

            Section("Shortcut") {
                HotKeyRecorderField(hotKey: $hotKey)
            }

            Section("Language") {
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
                    model.validateAndSaveAPIKey(apiKey, hotKey: hotKey, language: language, secondaryLanguage: secondaryLanguage) { success in
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
        .frame(width: 520)
        .onAppear {
            apiKey = model.settings.apiKey
            hotKey = model.settings.hotKey
            language = model.settings.language
            secondaryLanguage = model.settings.secondaryLanguage
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

        init(hotKey: Binding<HotKey>) {
            _hotKey = hotKey
        }

        @objc func startRecording(_ sender: NSButton) {
            button = sender
            sender.title = "Press new shortcut..."
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                guard !modifiers.isEmpty else { return nil }
                self.hotKey = HotKey(
                    keyCode: UInt32(event.keyCode),
                    modifiers: KeyCodeMap.carbonModifiers(from: modifiers)
                )
                self.button?.title = self.hotKey.displayString
                if let monitor = self.monitor {
                    NSEvent.removeMonitor(monitor)
                }
                self.monitor = nil
                return nil
            }
        }
    }
}
