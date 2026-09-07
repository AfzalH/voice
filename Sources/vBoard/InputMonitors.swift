import AppKit
import ApplicationServices
import Carbon

// MARK: - GlobalHotKeyMonitor

/// Monitors the two global shortcuts (push-to-talk and handsfree) with a single
/// CGEvent tap.
///
/// Push-to-talk semantics: the shortcut must be *held*. Recording begins on press;
/// release commits it. Two situations cancel instead of committing so that the
/// shortcut never interferes with normal use of the key:
///  - the key was released within `tapThreshold` (a tap, e.g. fn tap to switch
///    input source or show emoji);
///  - another key was pressed while the shortcut was held (a combination, e.g.
///    fn+F1 or right⌘+C).
///
/// Handsfree semantics: a *tap* toggles recording. For modifier-based shortcuts
/// (fn, right ⌘, ⌃⌥…) the toggle fires on release, and only if no other key was
/// pressed in between, so holding the modifier for a normal combination never
/// triggers it. For key+modifier shortcuts (⌥Space) it fires on key down, and the
/// key event is swallowed so the frontmost app does not also receive it.
///
/// Left and right modifier keys are told apart using the device-specific flag
/// bits macOS attaches to events (falling back to side-agnostic matching on
/// keyboards that do not report them).
///
/// Uses `.cgSessionEventTap` + `.headInsertEventTap` for highest-priority system-wide
/// interception, and a watchdog timer to re-enable the tap if macOS silently disables it.
final class GlobalHotKeyMonitor {
    /// Push-to-talk shortcut went down. Start capturing audio immediately.
    var onPushToTalkBegan: (() -> Void)?
    /// Push-to-talk shortcut ended. `cancelled` is true for taps and combinations.
    var onPushToTalkEnded: ((_ cancelled: Bool) -> Void)?
    /// Handsfree shortcut was tapped.
    var onHandsfreeToggled: (() -> Void)?

    /// Presses shorter than this are treated as taps, not push-to-talk holds.
    static let tapThreshold: TimeInterval = 0.2

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?

    private var pushToTalk: HotKey?
    private var handsfree: HotKey?

    /// Per-shortcut engagement state.
    private struct Engagement {
        var isEngaged = false
        var engagedAt: TimeInterval = 0
        /// Another key was pressed while engaged; the release must not fire.
        var interrupted = false
    }

    private var pushToTalkState = Engagement()
    private var handsfreeState = Engagement()
    private var fnIsDown = false

    // MARK: - Registration

    func register(pushToTalk: HotKey?, handsfree: HotKey?) throws {
        unregister()
        self.pushToTalk = pushToTalk
        self.handsfree = handsfree
        guard pushToTalk != nil || handsfree != nil else { return }

        let mask: CGEventMask =
              CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
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

                let swallow = monitor.handle(type: type, event: event)
                return swallow ? nil : Unmanaged.passUnretained(event)
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

    // MARK: - Event dispatch

    /// Returns true when the event must be swallowed (not delivered to the app).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // The Fn/Globe key arrives as flagsChanged (or keyDown/keyUp on some
        // configurations), always with key code 63.
        if keyCode == 63 {
            let wasDown = fnIsDown
            switch type {
            case .flagsChanged: fnIsDown = flags.contains(.maskSecondaryFn)
            case .keyDown:      fnIsDown = true
            case .keyUp:        fnIsDown = false
            default: break
            }
            if fnIsDown != wasDown {
                if let hotKey = pushToTalk, hotKey.isFnKey {
                    updatePushToTalk(pressed: fnIsDown, extended: false)
                }
                if let hotKey = handsfree, hotKey.isFnKey {
                    updateHandsfree(pressed: fnIsDown, extended: false)
                }
            }
            return false
        }

        switch type {
        case .flagsChanged:
            // Modifier-only chords engage/release as the held set changes.
            // Key+modifier shortcuts release when a required modifier lifts.
            if let hotKey = pushToTalk, !hotKey.isFnKey {
                if hotKey.isModifierOnly {
                    let match = Self.chordMatch(hotKey, flags: flags)
                    updatePushToTalk(pressed: match == .exact, extended: match == .superset)
                } else if pushToTalkState.isEngaged, !Self.modifiersMatch(hotKey, flags: flags) {
                    updatePushToTalk(pressed: false, extended: false)
                }
            }
            if let hotKey = handsfree, !hotKey.isFnKey, hotKey.isModifierOnly {
                let match = Self.chordMatch(hotKey, flags: flags)
                updateHandsfree(pressed: match == .exact, extended: match == .superset)
            }
            return false

        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            var swallow = false

            if let hotKey = pushToTalk, !hotKey.isFnKey, !hotKey.isModifierOnly, keyCode == hotKey.keyCode {
                if pushToTalkState.isEngaged {
                    swallow = true // auto-repeat while held
                } else if !isRepeat, Self.modifiersMatch(hotKey, flags: flags) {
                    updatePushToTalk(pressed: true, extended: false)
                    swallow = true
                }
            }
            if let hotKey = handsfree, !hotKey.isFnKey, !hotKey.isModifierOnly, keyCode == hotKey.keyCode,
               Self.modifiersMatch(hotKey, flags: flags)
            {
                if !isRepeat { onHandsfreeToggled?() }
                swallow = true
            }
            if swallow { return true }

            // Any other key pressed while a modifier-style shortcut is held means the
            // user is typing a combination — the shortcut must not fire.
            if !isRepeat {
                interruptPushToTalk()
                handsfreeState.interrupted = true
            }
            return false

        case .keyUp:
            var swallow = false
            if let hotKey = pushToTalk, !hotKey.isFnKey, !hotKey.isModifierOnly, keyCode == hotKey.keyCode {
                if pushToTalkState.isEngaged {
                    updatePushToTalk(pressed: false, extended: false)
                    swallow = true
                }
            }
            if let hotKey = handsfree, !hotKey.isFnKey, !hotKey.isModifierOnly, keyCode == hotKey.keyCode,
               Self.modifiersMatch(hotKey, flags: flags)
            {
                swallow = true
            }
            return swallow

        default:
            return false
        }
    }

    // MARK: - State machines

    /// `extended`: the chord is still held but an extra modifier was added.
    private func updatePushToTalk(pressed: Bool, extended: Bool) {
        if extended {
            interruptPushToTalk()
            return
        }
        if pressed && !pushToTalkState.isEngaged {
            pushToTalkState = Engagement(isEngaged: true, engagedAt: ProcessInfo.processInfo.systemUptime)
            onPushToTalkBegan?()
        } else if !pressed && pushToTalkState.isEngaged {
            let held = ProcessInfo.processInfo.systemUptime - pushToTalkState.engagedAt
            let alreadyEnded = pushToTalkState.interrupted // cancel was reported at interruption time
            let cancelled = held < Self.tapThreshold
            pushToTalkState = Engagement()
            if !alreadyEnded { onPushToTalkEnded?(cancelled) }
        }
    }

    private func interruptPushToTalk() {
        guard pushToTalkState.isEngaged, !pushToTalkState.interrupted else { return }
        pushToTalkState.interrupted = true
        // Stop right away so the combination the user is typing isn't recorded.
        onPushToTalkEnded?(true)
    }

    private func updateHandsfree(pressed: Bool, extended: Bool) {
        if extended {
            handsfreeState.interrupted = true
            return
        }
        if pressed && !handsfreeState.isEngaged {
            handsfreeState = Engagement(isEngaged: true, engagedAt: ProcessInfo.processInfo.systemUptime)
        } else if !pressed && handsfreeState.isEngaged {
            let fire = !handsfreeState.interrupted
            handsfreeState = Engagement()
            if fire { onHandsfreeToggled?() }
        }
    }

    // MARK: - Matching

    private enum ChordMatch { case none, exact, superset }

    /// How the currently held modifiers relate to a modifier-only shortcut.
    private static func chordMatch(_ hotKey: HotKey, flags: CGEventFlags) -> ChordMatch {
        let generic = carbonModifiers(from: flags)
        guard generic & hotKey.modifiers == hotKey.modifiers else { return .none }
        guard sidesMatch(hotKey, flags: flags) else { return .none }
        return generic == hotKey.modifiers ? .exact : .superset
    }

    /// Exact match of generic modifiers plus side check, for key+modifier shortcuts.
    private static func modifiersMatch(_ hotKey: HotKey, flags: CGEventFlags) -> Bool {
        carbonModifiers(from: flags) == hotKey.modifiers && sidesMatch(hotKey, flags: flags)
    }

    /// For side-specific shortcuts, verifies the required side is held using the
    /// device-specific flag bits. Keyboards that report no side bits pass.
    private static func sidesMatch(_ hotKey: HotKey, flags: CGEventFlags) -> Bool {
        let raw = flags.rawValue
        for key in hotKey.modifierKeys {
            let familyBits = ModifierKey.allCases
                .filter { $0.cgFlag == key.cgFlag }
                .reduce(UInt64(0)) { $0 | $1.deviceFlagBit }
            if raw & familyBits != 0, raw & key.deviceFlagBit == 0 {
                return false
            }
        }
        return true
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
        pushToTalk = nil
        handsfree = nil
        pushToTalkState = Engagement()
        handsfreeState = Engagement()
        fnIsDown = false
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
