import AppKit
import SwiftUI

// MARK: - RecordingIslandController

final class RecordingIslandController: NSObject {
    var onStopTapped: (() -> Void)?

    private var panel: NSPanel?
    private var islandView: RecordingIslandView?

    func show() {
        if panel == nil {
            createPanel()
        }
        guard let panel else { return }
        
        // Position near the top center of the screen (near notch, like Dynamic Island)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            let width: CGFloat = 320
            let height: CGFloat = 36
            let x = frame.midX - width / 2
            let y = frame.maxY - 48  // 48 points from top
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func updateLevel(_ level: Float) {
        islandView?.updateLevel(level)
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
        islandView.onStopTapped = { [weak self] in
            self?.onStopTapped?()
        }
        panel.contentView = islandView
        
        self.islandView = islandView
        self.panel = panel
    }
}

// MARK: - RecordingIslandView

final class RecordingIslandView: NSView {
    var onStopTapped: (() -> Void)?
    
    private var audioLevel: Float = 0.0
    private var barCount = 30
    private var barValues: [Float] = []
    private var displayLink: CVDisplayLink?
    private var stopButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        barValues = Array(repeating: 0.1, count: barCount)
        setupStopButton()
        setupDisplayLink()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        barValues = Array(repeating: 0.1, count: barCount)
        setupStopButton()
        setupDisplayLink()
    }

    deinit {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }

    func updateLevel(_ level: Float) {
        audioLevel = level
    }

    private func setupStopButton() {
        // Create a circular stop button on the right side
        let buttonSize: CGFloat = 28
        let buttonX = bounds.width - buttonSize - 4
        let buttonY = (bounds.height - buttonSize) / 2
        
        stopButton = NSButton(frame: NSRect(x: buttonX, y: buttonY, width: buttonSize, height: buttonSize))
        stopButton.autoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]
        stopButton.isBordered = false
        stopButton.wantsLayer = true
        stopButton.layer?.cornerRadius = buttonSize / 2
        stopButton.layer?.backgroundColor = NSColor.systemRed.cgColor
        stopButton.target = self
        stopButton.action = #selector(stopButtonClicked)
        
        // Add a stop icon using attributed string
        let font = NSFont.systemFont(ofSize: 12, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        stopButton.attributedTitle = NSAttributedString(string: "■", attributes: attributes)
        
        addSubview(stopButton)
    }

    @objc private func stopButtonClicked() {
        onStopTapped?()
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
        // Shift bars to the left and add new value
        barValues.removeFirst()
        
        // Add some randomness to make it look more natural
        let baseLevel = audioLevel * 0.8
        let randomVariation = Float.random(in: -0.08...0.08)
        let newValue = min(max(baseLevel + randomVariation, 0.08), 1.0)
        barValues.append(newValue)
        
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw black pill background
        let pillPath = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.black.withAlphaComponent(0.85).setFill()
        pillPath.fill()
        
        // Draw waveform in the left 80% of the pill
        let waveformWidth = bounds.width * 0.75
        let waveformHeight = bounds.height - 12
        let waveformY = (bounds.height - waveformHeight) / 2
        let waveformRect = NSRect(x: 12, y: waveformY, width: waveformWidth, height: waveformHeight)
        
        let barWidth = waveformRect.width / CGFloat(barCount)
        let spacing: CGFloat = 1.5
        
        // Create gradient colors matching the logo (coral → purple → blue)
        let coralColor = NSColor(red: 0.91, green: 0.40, blue: 0.40, alpha: 0.9)  // #E86666
        let purpleColor = NSColor(red: 0.60, green: 0.40, blue: 0.80, alpha: 0.9)  // #9966CC
        let blueColor = NSColor(red: 0.40, green: 0.40, blue: 0.87, alpha: 0.9)    // #6666DD
        
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
            
            // Calculate gradient position based on bar index (left to right)
            let gradientPosition = CGFloat(index) / CGFloat(barCount - 1)
            let barColor: NSColor
            
            if gradientPosition < 0.5 {
                // Interpolate between coral and purple
                let t = gradientPosition * 2.0
                barColor = NSColor(
                    red: coralColor.redComponent * (1 - t) + purpleColor.redComponent * t,
                    green: coralColor.greenComponent * (1 - t) + purpleColor.greenComponent * t,
                    blue: coralColor.blueComponent * (1 - t) + purpleColor.blueComponent * t,
                    alpha: 0.9
                )
            } else {
                // Interpolate between purple and blue
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

final class SettingsWindowManager {
    private var window: NSWindow?
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard let model else { return }
        // Always create a fresh window so onAppear re-loads current state.
        window?.close()
        let root = SettingsView(model: model)
        let hosting = NSHostingController(rootView: root)
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "SrizonVoice Settings"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 560, height: 360))
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    func hide() {
        window?.close()
        window = nil
    }
}
