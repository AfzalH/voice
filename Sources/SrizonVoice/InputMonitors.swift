import AppKit
import ApplicationServices
import Carbon

// MARK: - GlobalHotKeyMonitor

final class GlobalHotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var callback: (() -> Void)?
    private let signature = OSType(0x53564F58) // SVOX
    private let hotKeyID = UInt32(1)

    func register(hotKey: HotKey, callback: @escaping () -> Void) throws {
        unregister()
        self.callback = callback

        let hotKeyID = EventHotKeyID(signature: signature, id: self.hotKeyID)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { throw HotKeyError.registrationFailed }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                var hkID = EventHotKeyID()
                let result = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard result == noErr else { return noErr }
                let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                if hkID.signature == monitor.signature && hkID.id == monitor.hotKeyID {
                    monitor.callback?()
                }
                return noErr
            },
            1,
            &eventSpec,
            pointer,
            &eventHandlerRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        callback = nil
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

// MARK: - DoubleClickTextMonitor

/// Listens for double-clicks on text-editable elements and invokes a callback.
/// Uses CGEvent tap (works with Accessibility permission; no Input Monitoring needed).
final class DoubleClickTextMonitor {
    var onDoubleClickOnText: ((NSPoint) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        stop()
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                if type == .leftMouseDown {
                    let monitor = Unmanaged<DoubleClickTextMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                    let clickCount = Int(event.getIntegerValueField(.mouseEventClickState))
                    if clickCount == 2 {
                        let loc = event.location
                        let point = NSPoint(x: loc.x, y: loc.y)
                        if monitor.isTextElement(at: point) {
                            DispatchQueue.main.async { monitor.onDoubleClickOnText?(point) }
                        }
                    }
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

    private func isTextElement(at point: NSPoint) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &elementRef) == .success,
              let axElement = elementRef
        else { return false }
        return hasTextRole(axElement) || hasEditableText(axElement)
    }

    private func hasTextRole(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String
        else { return false }
        let textRoles = [
            kAXTextFieldRole,
            kAXTextAreaRole,
            kAXComboBoxRole,
            "AXWebArea",
        ]
        return textRoles.contains(role)
    }

    private func hasEditableText(_ element: AXUIElement) -> Bool {
        // Check if element has kAXSelectedTextAttribute or kAXValueAttribute (indicates editability)
        var selectedTextRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success {
            return true
        }
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
            return true
        }
        return tryDescendantsForEditableText(element, depth: 0)
    }

    private func tryDescendantsForEditableText(_ element: AXUIElement, depth: Int) -> Bool {
        guard depth < 3 else { return false }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return false }
        for child in children {
            // Check if child has editable attributes
            var selectedTextRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success {
                return true
            }
            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef) == .success {
                return true
            }
            if tryDescendantsForEditableText(child, depth: depth + 1) { return true }
        }
        return false
    }
}
