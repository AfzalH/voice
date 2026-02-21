import AppKit
import ApplicationServices
import Carbon

// MARK: - GlobalHotKeyMonitor

/// Monitors a global hotkey with press-and-release semantics using a unified CGEvent tap.
/// Supports regular key+modifier combos, modifier-only combos, and the Fn/Globe key.
/// `onKeyDown` fires when the hotkey is pressed, `onKeyUp` when released.
///
/// Uses `.cgSessionEventTap` + `.headInsertEventTap` for highest-priority system-wide
/// interception, and a watchdog timer to re-enable the tap if macOS silently disables it.
final class GlobalHotKeyMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var registeredHotKey: HotKey?
    private var isDown = false
    private var watchdogTimer: Timer?

    func register(hotKey: HotKey) throws {
        unregister()
        registeredHotKey = hotKey

        // Always listen for ALL event types so we never miss an event,
        // regardless of hotkey kind (Fn, modifier-only, or regular key).
        let mask: CGEventMask =
              CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

                // Re-enable tap if macOS disabled it
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard let hotKey = monitor.registeredHotKey else {
                    return Unmanaged.passUnretained(event)
                }

                if hotKey.isFnKey {
                    monitor.handleFnKey(type: type, event: event)
                } else if hotKey.isModifierOnly {
                    monitor.handleModifierOnly(event: event, hotKey: hotKey)
                } else {
                    monitor.handleRegularKey(type: type, event: event, hotKey: hotKey)
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else { throw HotKeyError.registrationFailed }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Watchdog: periodically ensure the tap stays enabled.
        // macOS can silently disable taps under load or after sleep.
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    // MARK: - Event handlers

    private func handleFnKey(type: CGEventType, event: CGEvent) {
        // The Fn/Globe key can arrive as either flagsChanged (modifier flag)
        // or keyDown/keyUp with key code 63, depending on macOS version and
        // System Settings > Keyboard configuration.
        if type == .flagsChanged {
            let isFnDown = event.flags.contains(.maskSecondaryFn)
            if isFnDown && !isDown {
                isDown = true
                onKeyDown?()
            } else if !isFnDown && isDown {
                isDown = false
                onKeyUp?()
            }
        } else {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 63 { // Fn/Globe key code
                if type == .keyDown && !isDown {
                    isDown = true
                    onKeyDown?()
                } else if type == .keyUp && isDown {
                    isDown = false
                    onKeyUp?()
                }
            }
        }
    }

    private func handleModifierOnly(event: CGEvent, hotKey: HotKey) {
        let currentMods = Self.carbonModifiers(from: event.flags)
        let required = hotKey.modifiers
        let allHeld = (currentMods & required) == required
        if allHeld && !isDown {
            isDown = true
            onKeyDown?()
        } else if !allHeld && isDown {
            isDown = false
            onKeyUp?()
        }
    }

    private func handleRegularKey(type: CGEventType, event: CGEvent, hotKey: HotKey) {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyDown && !isDown && keyCode == hotKey.keyCode {
            let currentMods = Self.carbonModifiers(from: event.flags)
            let required = hotKey.modifiers
            if (currentMods & required) == required {
                isDown = true
                onKeyDown?()
            }
        } else if type == .keyUp && isDown && keyCode == hotKey.keyCode {
            isDown = false
            onKeyUp?()
        } else if type == .flagsChanged && isDown {
            // Modifier released while key is held — stop recording
            let currentMods = Self.carbonModifiers(from: event.flags)
            let required = hotKey.modifiers
            if (currentMods & required) != required {
                isDown = false
                onKeyUp?()
            }
        }
    }

    private static func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.maskCommand) { value |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { value |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { value |= UInt32(optionKey) }
        if flags.contains(.maskControl) { value |= UInt32(controlKey) }
        return value
    }

    // MARK: - Teardown

    func unregister() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        registeredHotKey = nil
        isDown = false
    }
}

enum HotKeyError: Error {
    case registrationFailed
}

// MARK: - GlobalEscapeKeyMonitor

/// Monitors the Escape key globally using a CGEvent tap.
/// Unlike NSEvent.addGlobalMonitorForEvents, this works with just
/// Accessibility permission (no separate Input Monitoring needed).
final class GlobalEscapeKeyMonitor {
    var onEscapePressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        stop()

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                if type == .keyDown,
                   event.getIntegerValueField(.keyboardEventKeycode) == 53
                {
                    let monitor = Unmanaged<GlobalEscapeKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                    monitor.onEscapePressed?()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
