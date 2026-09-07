import AppKit
import SwiftUI

// MARK: - RecordingIslandController

/// Small black pill just above the Dock, ChatGPT-voice-mode style: a row of
/// white dots that grow into bars with the microphone level while recording,
/// and pulse in sequence while transcribing.
final class RecordingIslandController: NSObject {
    static let size = NSSize(width: 132, height: 52)
    private var panel: NSPanel?
    private var islandView: RecordingIslandView?

    func show() {
        if panel == nil {
            createPanel()
        }
        guard let panel else { return }
        position(panel)
        islandView?.setTranscribing(false)
        islandView?.startAnimating()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        islandView?.stopAnimating()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // A new show() may have started during the fade; only hide if it didn't.
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        })
    }

    func updateLevel(_ level: Float) {
        islandView?.updateLevel(level)
    }

    func showTranscribing() {
        if panel?.isVisible != true { show() }
        islandView?.setTranscribing(true)
        islandView?.startAnimating()
    }

    /// Centered horizontally, sitting just above the Dock (or the bottom edge
    /// when the Dock is hidden or on the side).
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = Self.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 10
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let islandView = RecordingIslandView(frame: panel.contentView?.bounds ?? .zero)
        islandView.autoresizingMask = [.width, .height]
        panel.contentView = islandView

        self.islandView = islandView
        self.panel = panel
    }
}

// MARK: - RecordingIslandView

final class RecordingIslandView: NSView {
    private static let dotCount = 6
    /// Bars are thin and tightly packed, like the ChatGPT voice pill.
    private static let dotSize: CGFloat = 3.5
    private static let dotSpacing: CGFloat = 4.5
    private static let maxBarHeight: CGFloat = 22
    /// Warm near-black pill and almond-silk bars from the SrizonVoice palette.
    private static let pillColor = NSColor(hex: 0x15110E, alpha: 0.96)
    private static let barColor = NSColor.voiceAlmondSilk

    private var audioLevel: Float = 0
    private var smoothedLevel: Float = 0
    /// Per-dot heights in 0...1 (0 = resting dot, 1 = full bar), eased every frame.
    private var barValues: [CGFloat] = Array(repeating: 0, count: RecordingIslandView.dotCount)
    private var targetValues: [CGFloat] = Array(repeating: 0, count: RecordingIslandView.dotCount)
    private var phase: CGFloat = 0
    private var frameCounter = 0
    private var displayLink: CVDisplayLink?
    private var isTranscribing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupDisplayLink()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupDisplayLink()
    }

    deinit {
        if let displayLink { CVDisplayLinkStop(displayLink) }
    }

    func updateLevel(_ level: Float) {
        audioLevel = min(max(level, 0), 1)
    }

    func setTranscribing(_ transcribing: Bool) {
        isTranscribing = transcribing
        if transcribing {
            targetValues = Array(repeating: 0, count: Self.dotCount)
        }
        needsDisplay = true
    }

    private func setupDisplayLink() {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<RecordingIslandView>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { view.tick() }
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        self.displayLink = link
    }

    /// Starts the animation. Only runs while the island is visible so no CPU is
    /// spent while idle in the menu bar.
    func startAnimating() {
        guard let displayLink, !CVDisplayLinkIsRunning(displayLink) else { return }
        CVDisplayLinkStart(displayLink)
    }

    func stopAnimating() {
        if let displayLink, CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }
        barValues = Array(repeating: 0, count: Self.dotCount)
        targetValues = barValues
        smoothedLevel = 0
    }

    private func tick() {
        frameCounter += 1
        phase += isTranscribing ? 0.09 : 0.05

        if !isTranscribing {
            // Fast attack, slower release, so speech onsets feel responsive.
            let attack: Float = audioLevel > smoothedLevel ? 0.35 : 0.08
            smoothedLevel += (audioLevel - smoothedLevel) * attack

            if frameCounter % 4 == 0 {
                // Each dot gets its own target around the current level so the
                // row looks alive rather than a uniform block. Silence → flat dots.
                let level = CGFloat(min(smoothedLevel * 1.6, 1))
                for index in 0..<Self.dotCount {
                    let seed = CGFloat(index) * 1.7
                    let wobble = (sin(phase * 2.3 + seed) + sin(phase * 3.7 + seed * 0.6)) * 0.25 + 0.5 // 0...1
                    let centerBias = 1 - abs(CGFloat(index) - CGFloat(Self.dotCount - 1) / 2) / CGFloat(Self.dotCount) * 0.6
                    let value = level * (0.45 + 0.55 * wobble) * centerBias
                    targetValues[index] = level < 0.04 ? 0 : min(max(value, 0.12), 1)
                }
            }
        }

        for index in 0..<Self.dotCount {
            barValues[index] += (targetValues[index] - barValues[index]) * 0.25
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pill = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        Self.pillColor.setFill()
        pill.fill()

        let totalWidth = CGFloat(Self.dotCount) * Self.dotSize + CGFloat(Self.dotCount - 1) * Self.dotSpacing
        let startX = (bounds.width - totalWidth) / 2
        let midY = bounds.midY

        for index in 0..<Self.dotCount {
            let x = startX + CGFloat(index) * (Self.dotSize + Self.dotSpacing)
            let height: CGFloat
            let alpha: CGFloat
            if isTranscribing {
                // Travelling pulse: dots brighten one after another while we wait.
                let wave = (sin(phase - CGFloat(index) * 0.75) + 1) / 2
                height = Self.dotSize
                alpha = 0.3 + 0.7 * wave
            } else {
                height = Self.dotSize + barValues[index] * (Self.maxBarHeight - Self.dotSize)
                // Taller bars glow slightly brighter.
                alpha = 0.78 + 0.22 * barValues[index]
            }
            let rect = NSRect(x: x, y: midY - height / 2, width: Self.dotSize, height: height)
            Self.barColor.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: rect, xRadius: Self.dotSize / 2, yRadius: Self.dotSize / 2).fill()
        }
    }
}

// MARK: - SettingsWindowManager

final class SettingsWindowManager: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard let model else { return }
        window?.close()

        // Show dock icon while settings is open
        NSApp.setActivationPolicy(.regular)

        let root = SettingsView(model: model)
        let hosting = NSHostingController(rootView: root)
        // Prevent NSHostingView from updating the window's min/max content
        // size during constraint updates.  Without this, the hosting view
        // re-enters the constraint system via
        // updateWindowContentSizeExtremaIfNecessary → setNeedsUpdateConstraints
        // while AppKit is already inside an update-constraints pass, crashing
        // in _postWindowNeedsUpdateConstraints.
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = .intrinsicContentSize
        }
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "SrizonVoice Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 780, height: 610))
        newWindow.minSize = NSSize(width: 720, height: 520)
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .normal
        newWindow.delegate = self
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    func hide() {
        guard let window else { return }
        // Order the window out first so that AppKit's display-cycle
        // observer stops processing constraint updates for it.
        // Without this, the NSHostingView can fire updateConstraints
        // after the content view controller is detached, crashing in
        // _postWindowNeedsUpdateConstraints.
        window.orderOut(nil)
        window.contentViewController = nil
        window.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
        model?.onSettingsWindowClosed()
        // Switch back to menu-bar-only mode
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - PostProcessingPanelController

final class PostProcessingBubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PostProcessingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var panelModel: PostProcessingPanelModel?
    private var onClosed: (() -> Void)?

    func show(
        transcript: String,
        anchorPoint: NSPoint?,
        translationLanguage: LanguageOption,
        favoriteTranslationLanguages: [LanguageOption],
        customPrompts: [CustomPostProcessingPrompt],
        processAction: @escaping (String, PostProcessingAction) async throws -> String,
        insertText: @escaping (String) -> Void,
        savePrompt: @escaping (String, String) -> [CustomPostProcessingPrompt],
        onClosed: @escaping () -> Void
    ) {
        hide()
        self.onClosed = onClosed

        let model = PostProcessingPanelModel(
            transcript: transcript,
            translationLanguage: translationLanguage,
            favoriteTranslationLanguages: favoriteTranslationLanguages,
            customPrompts: customPrompts,
            processAction: processAction,
            insertText: insertText,
            savePrompt: savePrompt,
            closePanel: { [weak self] in
                self?.hide()
            }
        )
        let hosting = NSHostingController(rootView: PostProcessingPanelView(model: model))
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = .intrinsicContentSize
        }

        let newPanel = PostProcessingBubblePanel(
            contentRect: NSRect(x: 0, y: 0, width: 662, height: 742),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "Post-process Transcript"
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.isMovableByWindowBackground = true
        newPanel.isReleasedWhenClosed = false
        newPanel.level = .statusBar
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        newPanel.contentViewController = hosting
        newPanel.delegate = self
        position(newPanel, near: anchorPoint)

        panelModel = model
        panel = newPanel
        NSApp.activate(ignoringOtherApps: true)
        newPanel.makeKeyAndOrderFront(nil)
        newPanel.orderFrontRegardless()
    }

    func hide() {
        guard let panel else { return }
        panel.close()
    }

    private func position(_ panel: NSPanel, near anchorPoint: NSPoint?) {
        guard let screen = screen(containing: anchorPoint) ?? NSScreen.main ?? NSScreen.screens.first else {
            panel.center()
            return
        }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        guard let anchorPoint else {
            let x = frame.midX - size.width / 2
            let y = frame.maxY - size.height - 70
            panel.setFrameOrigin(NSPoint(x: x, y: max(frame.minY + 20, y)))
            return
        }

        let padding: CGFloat = 14
        let rightX = anchorPoint.x + 18
        let leftX = anchorPoint.x - size.width - 18
        let preferredX = rightX + size.width <= frame.maxX - padding ? rightX : leftX
        let x = min(max(preferredX, frame.minX + padding), frame.maxX - size.width - padding)
        let preferredY = anchorPoint.y - size.height + 48
        let y = min(max(preferredY, frame.minY + padding), frame.maxY - size.height - padding)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func screen(containing point: NSPoint?) -> NSScreen? {
        guard let point else { return nil }
        return NSScreen.screens.first { $0.visibleFrame.contains(point) }
    }

    func windowWillClose(_ notification: Notification) {
        panel?.contentViewController = nil
        panel = nil
        panelModel = nil
        let closeHandler = onClosed
        onClosed = nil
        closeHandler?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Closing while a request is in flight cancels it rather than being blocked.
        panelModel?.cancelProcessing()
        return true
    }
}

// MARK: - PostProcessingPanelModel

@MainActor
final class PostProcessingPanelModel: ObservableObject {
    let transcript: String

    @Published var selectedLanguage: LanguageOption
    @Published var favoriteTranslationLanguages: [LanguageOption]
    @Published var customPromptTitle = ""
    @Published var customPromptBody = ""
    @Published var customPrompts: [CustomPostProcessingPrompt]
    @Published var isProcessing = false
    @Published var errorMessage: String?

    @Published var currentText: String
    @Published private var history: [String] = []

    private let processAction: (String, PostProcessingAction) async throws -> String
    private let insertText: (String) -> Void
    private let savePrompt: (String, String) -> [CustomPostProcessingPrompt]
    private let closePanel: () -> Void
    private var processingTask: Task<Void, Never>?

    init(
        transcript: String,
        translationLanguage: LanguageOption,
        favoriteTranslationLanguages: [LanguageOption],
        customPrompts: [CustomPostProcessingPrompt],
        processAction: @escaping (String, PostProcessingAction) async throws -> String,
        insertText: @escaping (String) -> Void,
        savePrompt: @escaping (String, String) -> [CustomPostProcessingPrompt],
        closePanel: @escaping () -> Void
    ) {
        self.transcript = transcript
        self.currentText = transcript
        self.selectedLanguage = translationLanguage
        self.favoriteTranslationLanguages = favoriteTranslationLanguages
        self.customPrompts = customPrompts
        self.processAction = processAction
        self.insertText = insertText
        self.savePrompt = savePrompt
        self.closePanel = closePanel
    }

    var canRunCustomPrompt: Bool {
        !customPromptBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canUndo: Bool {
        !history.isEmpty && !isProcessing
    }

    func insertCurrentText() {
        guard !isProcessing else { return }
        insertText(currentText)
    }

    func cancel() {
        cancelProcessing()
        closePanel()
    }

    /// Cancels any in-flight post-processing request without closing the panel.
    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
    }

    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        currentText = previous
        errorMessage = nil
    }

    func run(_ action: PostProcessingAction) {
        guard !isProcessing else { return }
        let sourceText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            errorMessage = "There is no text to post-process."
            return
        }

        isProcessing = true
        errorMessage = nil

        processingTask = Task {
            do {
                let processed = try await processAction(sourceText, action)
                await MainActor.run {
                    // Bail if the request was cancelled (Stop pressed or panel closed).
                    guard !Task.isCancelled else { return }
                    self.processingTask = nil
                    self.isProcessing = false
                    let trimmed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        self.errorMessage = "Post-processing returned empty text."
                        return
                    }
                    self.history.append(self.currentText)
                    self.currentText = trimmed
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.processingTask = nil
                    self.isProcessing = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func runCustomPrompt() {
        let prompt = customPromptBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        run(.custom(title: customPromptTitle, prompt: prompt))
    }

    func saveCurrentPrompt() {
        let updated = savePrompt(customPromptTitle, customPromptBody)
        customPrompts = updated
        if customPromptTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customPromptTitle = updated.last?.title ?? ""
        }
    }
}

// MARK: - PostProcessingPanelView

struct PostProcessingPanelView: View {
    @ObservedObject var model: PostProcessingPanelModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(VoiceTheme.raisedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(VoiceTheme.outlineVariant.opacity(0.78), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.50 : 0.18),
                    radius: 22,
                    x: 0,
                    y: 14
                )
                .shadow(color: VoiceTheme.primary.opacity(colorScheme == .dark ? 0.12 : 0.10), radius: 7, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 14) {
                header
                currentTextEditor
                quickActions
                savedPrompts
                customPromptEditor
                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 18)
            // Disable only the content while processing — the overlay's Stop button
            // sits outside this so it stays tappable to cancel an in-flight request.
            .disabled(model.isProcessing)

            if model.isProcessing {
                processingOverlay
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(50)
        .frame(width: 662, height: 742)
        .foregroundStyle(VoiceTheme.onSurface)
        .tint(VoiceTheme.primary)
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text("Post-process transcript")
                .font(.title3.weight(.semibold))
            Spacer()
        }
    }

    private var currentTextEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Current Text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VoiceTheme.secondaryText)
                Spacer()
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(VoiceQuietButtonStyle())
                .disabled(!model.canUndo)
            }
            TextEditor(text: $model.currentText)
                .font(.body)
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VoiceTheme.previewCanvas.opacity(colorScheme == .dark ? 0.44 : 0.40))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(VoiceTheme.outlineVariant.opacity(0.85), lineWidth: 1)
                )
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VoiceTheme.secondaryText)
            HStack(spacing: 8) {
                actionButton("Clean up", systemImage: "wand.and.stars") {
                    model.run(.cleanUp)
                }
                actionButton("Emoji", systemImage: "face.smiling") {
                    model.run(.addEmoji)
                }
                actionButton("Casual", systemImage: "bubble.left.and.bubble.right") {
                    model.run(.makeCasual)
                }
            }
            HStack(spacing: 8) {
                actionButton("Formal", systemImage: "doc.text") {
                    model.run(.makeFormal)
                }
                actionButton("Technical", systemImage: "cpu") {
                    model.run(.makeTechnical)
                }
                actionButton("Compact", systemImage: "text.badge.minus") {
                    model.run(.makeCompact)
                }
            }
            // Quick translations: recent + favorite languages, two per row.
            ForEach(Array(stride(from: 0, to: min(model.favoriteTranslationLanguages.count, 4), by: 2)), id: \.self) { start in
                HStack(spacing: 8) {
                    ForEach(model.favoriteTranslationLanguages[start..<min(start + 2, model.favoriteTranslationLanguages.count)], id: \.self) { language in
                        translationButton(language) {
                            model.run(.translate(language))
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Picker("Translate to", selection: $model.selectedLanguage) {
                    ForEach(LanguageOption.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .frame(maxWidth: .infinity)
                Button {
                    model.run(.translate(model.selectedLanguage))
                } label: {
                    HStack(spacing: 8) {
                        Text(model.selectedLanguage.flag)
                        Text("Translate Selected")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(VoiceSoftButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var savedPrompts: some View {
        if !model.customPrompts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Prompts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VoiceTheme.secondaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.customPrompts) { prompt in
                            Button(prompt.title) {
                                model.run(.custom(title: prompt.title, prompt: prompt.prompt))
                            }
                            .buttonStyle(VoicePillButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var customPromptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Prompt")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VoiceTheme.secondaryText)
            TextField("Prompt name", text: $model.customPromptTitle)
            TextEditor(text: $model.customPromptBody)
                .font(.system(.body, design: .monospaced))
                .frame(height: 88)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(VoiceTheme.surface.opacity(colorScheme == .dark ? 0.44 : 0.74))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(VoiceTheme.outlineVariant.opacity(0.85), lineWidth: 1)
                )
            HStack {
                Button {
                    model.saveCurrentPrompt()
                } label: {
                    Label("Save Prompt", systemImage: "plus")
                }
                .buttonStyle(VoiceQuietButtonStyle())
                .disabled(!model.canRunCustomPrompt)

                Spacer()

                Button {
                    model.runCustomPrompt()
                } label: {
                    Label("Run Custom", systemImage: "play.fill")
                }
                .buttonStyle(VoicePrimaryButtonStyle())
                .disabled(!model.canRunCustomPrompt)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(VoiceTheme.error)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") {
                model.cancel()
            }
            .buttonStyle(VoiceQuietButtonStyle())
            Button {
                model.insertCurrentText()
            } label: {
                Label("Copy and Insert", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(VoicePrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: [.command])

            shortcutKeycap
        }
    }

    private var shortcutKeycap: some View {
        HStack(spacing: 4) {
            Text("⌘ Return")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(VoiceTheme.secondaryText)
        .padding(.leading, 2)
        .accessibilityLabel("Command Return")
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.28 : 0.14)
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("Post-processing...")
                    .font(.callout)
                Button("Stop") {
                    model.cancelProcessing()
                }
                .controlSize(.small)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(VoiceTheme.raisedSurface)
                    .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
            )
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(VoiceSoftButtonStyle())
    }

    private func translationButton(
        _ language: LanguageOption,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(language.flag)
                Text("Translate to \(language.plainName)")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(VoiceSoftButtonStyle())
    }
}
