import AppKit
import Combine
import SwiftUI

@main
struct SrizonVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All UI is driven by the NSStatusItem managed in AppDelegate.
        // An empty Settings scene satisfies SwiftUI's requirement for at
        // least one scene while keeping the app as a pure menu-bar utility.
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

/// Manages the menu-bar status item, popover, app model, and lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var appModel: AppModel!

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var animationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var tick = 0

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        appModel = AppModel()
        setupAppIcon()
        setupStatusItem()

        if appModel.settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // First launch / no API key — show as a regular app with dock icon
            NSApp.setActivationPolicy(.regular)
            appModel.presentSettingsWindow()
        } else {
            // Already configured — run as menu-bar-only
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        appModel?.presentSettingsWindow()
        return false
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        // `autosaveName` lets macOS persist the user's preferred position in
        // the menu bar across launches.  This is the single most effective way
        // to keep the icon visible when the menu bar is crowded — the system
        // will try to honour the saved slot even when space is tight.
        statusItem.autosaveName = "SrizonVoiceStatusItem"

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "SrizonVoice"
            )
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked)
        }

        setupPopover()
        observeModelChanges()
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(model: appModel)
        )
    }

    private func observeModelChanges() {
        appModel.$isDictating
            .receive(on: RunLoop.main)
            .sink { [weak self] isDictating in
                self?.handleDictationStateChange(isDictating)
            }
            .store(in: &cancellables)
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            // Let keyboard events (e.g. Escape) reach the popover.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Icon Animation

    private func handleDictationStateChange(_ isDictating: Bool) {
        if isDictating {
            startIconAnimation()
        } else {
            stopIconAnimation()
            setStaticIcon()
        }
    }

    private func setStaticIcon() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: "SrizonVoice"
        )
        button.image?.isTemplate = true
        button.title = ""
    }

    private func startIconAnimation() {
        tick = 0
        updateAnimatedIcon()
        animationTimer = Timer.scheduledTimer(
            withTimeInterval: 0.12,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick += 1
                self?.updateAnimatedIcon()
            }
        }
    }

    private func stopIconAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func updateAnimatedIcon() {
        guard let button = statusItem.button else { return }
        let level = appModel.audioLevel
        let code = appModel.settings.language.code

        button.image = Self.makeWaveformImage(level: level, tick: tick)

        // Show non-English language code next to the waveform.
        if code.uppercased() != "EN" {
            button.title = code.uppercased()
        } else {
            button.title = ""
        }
    }

    /// Renders the audio-level waveform as a compact template `NSImage`,
    /// replicating the original SwiftUI `MenuBarIconView` animation.
    private static func makeWaveformImage(level: Float, tick: Int) -> NSImage {
        let imgWidth: CGFloat = 18
        let imgHeight: CGFloat = 18
        let image = NSImage(
            size: NSSize(width: imgWidth, height: imgHeight),
            flipped: false
        ) { _ in
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 2
            let multipliers: [CGFloat] = [0.9, 1.2, 0.8]
            let totalWidth = barWidth * 3 + spacing * 2
            let startX = (imgWidth - totalWidth) / 2

            for i in 0 ..< 3 {
                let phase = CGFloat((tick + i) % 3) * 0.08
                let normalized = min(max(CGFloat(level), 0.05), 1.0)
                let barHeight = 4 + (normalized + phase) * 8 * multipliers[i]
                let clampedHeight = min(max(barHeight, 3), 13)

                let x = startX + CGFloat(i) * (barWidth + spacing)
                let y = (imgHeight - clampedHeight) / 2

                let barRect = NSRect(
                    x: x, y: y,
                    width: barWidth, height: clampedHeight
                )
                NSColor.black.setFill()
                NSBezierPath(
                    roundedRect: barRect,
                    xRadius: barWidth / 2,
                    yRadius: barWidth / 2
                ).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - App Icon

    /// Creates a simple programmatic app icon so SrizonVoice is recognizable
    /// in permission dialogs, Activity Monitor, and the Dock (if shown).
    private func setupAppIcon() {
        let size = NSSize(width: 256, height: 256)
        let icon = NSImage(size: size, flipped: false) { rect in
            // Blue rounded-rectangle background
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 48, yRadius: 48).fill()

            // White microphone symbol via SF Symbols
            let config = NSImage.SymbolConfiguration(
                pointSize: 140, weight: .medium
            )
            .applying(
                NSImage.SymbolConfiguration(hierarchicalColor: .white)
            )
            if let mic = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: nil
            )?
            .withSymbolConfiguration(config) {
                mic.isTemplate = false
                let micSize = mic.size
                let origin = NSPoint(
                    x: (rect.width - micSize.width) / 2,
                    y: (rect.height - micSize.height) / 2
                )
                mic.draw(
                    at: origin, from: .zero,
                    operation: .sourceOver, fraction: 1.0
                )
            }
            return true
        }
        NSApp.applicationIconImage = icon
    }
}
