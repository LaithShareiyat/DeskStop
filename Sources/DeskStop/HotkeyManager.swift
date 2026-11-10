import Carbon.HIToolbox
import AppKit

struct HotkeyModifiers: OptionSet {
    let rawValue: UInt32
    static let command = HotkeyModifiers(rawValue: UInt32(cmdKey))
    static let option  = HotkeyModifiers(rawValue: UInt32(optionKey))
    static let control = HotkeyModifiers(rawValue: UInt32(controlKey))
    static let shift   = HotkeyModifiers(rawValue: UInt32(shiftKey))
}

/// Manages many global hotkeys keyed by caller-supplied string ids (we use
/// preset names). Each registered chord fires its own callback.
final class HotkeyManager {
    private struct Entry {
        let ref: EventHotKeyRef
        let id: UInt32
        let handler: () -> Void
    }

    private static let signature: OSType = 0x44504B59 // 'DPKY'
    private var nextID: UInt32 = 1
    private var entriesByName: [String: Entry] = [:]
    private var handlersByID: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false

    /// Registers (or replaces) a global chord under `name`. Returns true on
    /// success; false if Carbon rejected the registration (usually because the
    /// chord is already claimed system-wide).
    @discardableResult
    func register(name: String,
                  keyCode: UInt32,
                  modifiers: HotkeyModifiers,
                  action: @escaping () -> Void) -> Bool {
        unregister(name: name)
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode,
                                         modifiers.rawValue,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref = ref else {
            NSLog("DeskStop RegisterEventHotKey('\(name)') failed: \(status)")
            return false
        }
        entriesByName[name] = Entry(ref: ref, id: id, handler: action)
        handlersByID[id] = action
        return true
    }

    func unregister(name: String) {
        guard let entry = entriesByName.removeValue(forKey: name) else { return }
        handlersByID.removeValue(forKey: entry.id)
        UnregisterEventHotKey(entry.ref)
    }

    func unregisterAll() {
        for (_, entry) in entriesByName {
            UnregisterEventHotKey(entry.ref)
        }
        entriesByName.removeAll()
        handlersByID.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        handlersByID[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(),
                            { _, event, userData in
                                guard let userData = userData, let event = event else { return noErr }
                                var hkID = EventHotKeyID()
                                let err = GetEventParameter(event,
                                                            EventParamName(kEventParamDirectObject),
                                                            EventParamType(typeEventHotKeyID),
                                                            nil,
                                                            MemoryLayout<EventHotKeyID>.size,
                                                            nil,
                                                            &hkID)
                                guard err == noErr else { return noErr }
                                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                                manager.fire(id: hkID.id)
                                return noErr
                            },
                            1,
                            &eventType,
                            selfPtr,
                            nil)
    }
}
