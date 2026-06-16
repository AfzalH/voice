import AppKit
import SwiftUI

// MARK: - RecordingIslandController

final class RecordingIslandController: NSObject {
    private var panel: NSPanel?
    private var islandView: RecordingIslandView?

    func show() {
        if panel == nil {
            createPanel()
        }
        guard let panel else { return }
        
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let width: CGFloat = 320
            let height: CGFloat = 36
            let x = frame.midX - width / 2
            let y = frame.maxY - 48
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
        islandView?.setTranscribing(false)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func updateLevel(_ level: Float) {
        islandView?.updateLevel(level)
    }

    func showTranscribing() {
        islandView?.setTranscribing(true)
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 36),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
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
    private var audioLevel: Float = 0.0
    private var barCount = 30
    private var barValues: [Float] = []
    private var displayLink: CVDisplayLink?
    private var isTranscribing = false
    private var transcribingDots = 0
    private var transcribingTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        barValues = Array(repeating: 0.1, count: barCount)
        setupDisplayLink()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        barValues = Array(repeating: 0.1, count: barCount)
        setupDisplayLink()
    }

    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        transcribingTimer?.invalidate()
    }

    func updateLevel(_ level: Float) {
        audioLevel = level
    }

    func setTranscribing(_ transcribing: Bool) {
        isTranscribing = transcribing
        if transcribing {
            transcribingDots = 0
            transcribingTimer?.invalidate()
            transcribingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.transcribingDots = (self.transcribingDots + 1) % 4
                self.needsDisplay = true
            }
        } else {
            transcribingTimer?.invalidate()
            transcribingTimer = nil
        }
        needsDisplay = true
    }

    private func setupDisplayLink() {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        guard let link = displayLink else { return }
        
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<RecordingIslandView>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                view.animateBars()
            }
            return kCVReturnSuccess
        }
        
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, callback, userInfo)
        CVDisplayLinkStart(link)
        self.displayLink = link
    }

    private func animateBars() {
        guard !isTranscribing else { return }
        barValues.removeFirst()
        
        let baseLevel = audioLevel
        let randomVariation = Float.random(in: -0.12...0.12)
        let newValue = min(max(baseLevel + randomVariation, 0.10), 1.0)
        barValues.append(newValue)
        
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw black pill background
        let pillPath = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.black.withAlphaComponent(0.85).setFill()
        pillPath.fill()

        if isTranscribing {
            drawTranscribingState()
        } else {
            drawWaveform()
        }
    }

    private func drawTranscribingState() {
        let dots = String(repeating: ".", count: transcribingDots)
        let text = "Transcribing\(dots)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()
        let x = (bounds.width - textSize.width) / 2
        let y = (bounds.height - textSize.height) / 2
        attrString.draw(at: NSPoint(x: x, y: y))

        // Draw a small spinning indicator on the left
        let indicatorSize: CGFloat = 14
        let indicatorX: CGFloat = 16
        let indicatorY = (bounds.height - indicatorSize) / 2
        let indicatorRect = NSRect(x: indicatorX, y: indicatorY, width: indicatorSize, height: indicatorSize)
        
        let purpleColor = NSColor(red: 0.60, green: 0.40, blue: 0.80, alpha: 0.9)
        purpleColor.setStroke()
        let arc = NSBezierPath()
        let center = NSPoint(x: indicatorRect.midX, y: indicatorRect.midY)
        let radius = indicatorSize / 2 - 1
        let startAngle = CGFloat(transcribingDots) * 90.0
        arc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: startAngle + 270, clockwise: false)
        arc.lineWidth = 2
        arc.stroke()
    }

    private func drawWaveform() {
        let waveformWidth = bounds.width - 24
        let waveformHeight = bounds.height - 12
        let waveformY = (bounds.height - waveformHeight) / 2
        let waveformRect = NSRect(x: 12, y: waveformY, width: waveformWidth, height: waveformHeight)
        
        let barWidth = waveformRect.width / CGFloat(barCount)
        let spacing: CGFloat = 1.5
        
        let coralColor = NSColor(red: 0.91, green: 0.40, blue: 0.40, alpha: 0.9)
        let purpleColor = NSColor(red: 0.60, green: 0.40, blue: 0.80, alpha: 0.9)
        let blueColor = NSColor(red: 0.40, green: 0.40, blue: 0.87, alpha: 0.9)
        
        for (index, value) in barValues.enumerated() {
            let x = waveformRect.minX + CGFloat(index) * barWidth
            let barHeight = CGFloat(value) * waveformRect.height
            let y = waveformRect.minY + (waveformRect.height - barHeight) / 2
            
            let rect = CGRect(
                x: x + spacing / 2,
                y: y,
                width: barWidth - spacing,
                height: barHeight
            )
            
            let gradientPosition = CGFloat(index) / CGFloat(barCount - 1)
            let barColor: NSColor
            
            if gradientPosition < 0.5 {
                let t = gradientPosition * 2.0
                barColor = NSColor(
                    red: coralColor.redComponent * (1 - t) + purpleColor.redComponent * t,
                    green: coralColor.greenComponent * (1 - t) + purpleColor.greenComponent * t,
                    blue: coralColor.blueComponent * (1 - t) + purpleColor.blueComponent * t,
                    alpha: 0.9
                )
            } else {
                let t = (gradientPosition - 0.5) * 2.0
                barColor = NSColor(
                    red: purpleColor.redComponent * (1 - t) + blueColor.redComponent * t,
                    green: purpleColor.greenComponent * (1 - t) + blueColor.greenComponent * t,
                    blue: purpleColor.blueComponent * (1 - t) + blueColor.blueComponent * t,
                    alpha: 0.9
                )
            }
            
            barColor.setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            path.fill()
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
        newWindow.setContentSize(NSSize(width: 750, height: 550))
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

@MainActor
final class PostProcessingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var panelModel: PostProcessingPanelModel?
    private var onClosed: (() -> Void)?

    func show(
        transcript: String,
        targetAppName: String,
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
            targetAppName: targetAppName,
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

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 610),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "Post-process Transcript"
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.isReleasedWhenClosed = false
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.contentViewController = hosting
        newPanel.delegate = self
        position(newPanel)

        panelModel = model
        panel = newPanel
        NSApp.activate(ignoringOtherApps: true)
        newPanel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        panel.close()
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.center()
            return
        }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - 70
        panel.setFrameOrigin(NSPoint(x: x, y: max(frame.minY + 20, y)))
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
        !(panelModel?.isProcessing ?? false)
    }
}

// MARK: - PostProcessingPanelModel

@MainActor
final class PostProcessingPanelModel: ObservableObject {
    let transcript: String
    let targetAppName: String

    @Published var selectedLanguage: LanguageOption
    @Published var favoriteTranslationLanguages: [LanguageOption]
    @Published var customPromptTitle = ""
    @Published var customPromptBody = ""
    @Published var customPrompts: [CustomPostProcessingPrompt]
    @Published var isProcessing = false
    @Published var errorMessage: String?

    @Published var currentText: String
    @Published var autoInsertAfterProcessing = false
    @Published private var history: [String] = []

    private let processAction: (String, PostProcessingAction) async throws -> String
    private let insertText: (String) -> Void
    private let savePrompt: (String, String) -> [CustomPostProcessingPrompt]
    private let closePanel: () -> Void

    init(
        transcript: String,
        targetAppName: String,
        translationLanguage: LanguageOption,
        favoriteTranslationLanguages: [LanguageOption],
        customPrompts: [CustomPostProcessingPrompt],
        processAction: @escaping (String, PostProcessingAction) async throws -> String,
        insertText: @escaping (String) -> Void,
        savePrompt: @escaping (String, String) -> [CustomPostProcessingPrompt],
        closePanel: @escaping () -> Void
    ) {
        self.transcript = transcript
        self.targetAppName = targetAppName
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
        guard !isProcessing else { return }
        closePanel()
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

        Task {
            do {
                let processed = try await processAction(sourceText, action)
                await MainActor.run {
                    self.isProcessing = false
                    let trimmed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        self.errorMessage = "Post-processing returned empty text."
                        return
                    }
                    self.history.append(self.currentText)
                    self.currentText = trimmed
                    if self.autoInsertAfterProcessing {
                        self.insertText(trimmed)
                    }
                }
            } catch {
                await MainActor.run {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            currentTextEditor
            quickActions
            savedPrompts
            customPromptEditor
            footer
        }
        .padding(18)
        .frame(width: 540, height: 610)
        .disabled(model.isProcessing)
        .overlay(alignment: .center) {
            if model.isProcessing {
                processingOverlay
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Post-process transcript")
                    .font(.title3.weight(.semibold))
                Text(model.targetAppName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Auto-insert", isOn: $model.autoInsertAfterProcessing)
                .toggleStyle(.checkbox)
        }
    }

    private var currentTextEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Current Text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
            }
            TextEditor(text: $model.currentText)
                .font(.body)
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
            HStack(spacing: 8) {
                ForEach(Array(model.favoriteTranslationLanguages.prefix(2).enumerated()), id: \.offset) { _, language in
                    actionButton("Translate to \(language.plainName)", systemImage: "globe") {
                        model.run(.translate(language))
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
                    Label("Translate Selected", systemImage: "globe")
                }
            }
        }
    }

    @ViewBuilder
    private var savedPrompts: some View {
        if !model.customPrompts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Prompts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.customPrompts) { prompt in
                            Button(prompt.title) {
                                model.run(.custom(title: prompt.title, prompt: prompt.prompt))
                            }
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
                .foregroundStyle(.secondary)
            TextField("Prompt name", text: $model.customPromptTitle)
            TextEditor(text: $model.customPromptBody)
                .font(.system(.body, design: .monospaced))
                .frame(height: 88)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            HStack {
                Button {
                    model.saveCurrentPrompt()
                } label: {
                    Label("Save Prompt", systemImage: "plus")
                }
                .disabled(!model.canRunCustomPrompt)

                Spacer()

                Button {
                    model.runCustomPrompt()
                } label: {
                    Label("Run Custom", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRunCustomPrompt)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") {
                model.cancel()
            }
            Button {
                model.insertCurrentText()
            } label: {
                Label("Insert Transcript", systemImage: "text.insert")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("Post-processing...")
                    .font(.callout)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 14)
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
    }
}
