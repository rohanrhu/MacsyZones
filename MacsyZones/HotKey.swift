//
// MacsyZones, macOS system utility for managing windows on your Mac.
//
// https://macsyzones.com
//
// Copyright © 2024, Oğuzhan Eroğlu <meowingcate@gmail.com> (https://meowingcat.io)
//
// This file is part of MacsyZones.
// Licensed under GNU General Public License v3.0
// See LICENSE file.
//

import Carbon
import Cocoa
import OSLog

class GlobalHotkey: Identifiable, Equatable {
    static var handler: EventHandlerUPP = { _, eventRef, _ in
        var eventHotkeyId = EventHotKeyID()
        
        GetEventParameter(eventRef,
                          EventParamName(kEventParamDirectObject),
                          EventParamType(typeEventHotKeyID),
                          nil,
                          MemoryLayout<EventHotKeyID>.size,
                          nil,
                          &eventHotkeyId)
        
        guard let hotkey = (hotkeys.values.first { $0.hotkeyId == eventHotkeyId.id }) else {
            debugLog("No matching hotkey found for event")
            return noErr
        }
        
        debugLog("Hotkey pressed: signature=\(String(format: "%X", eventHotkeyId.signature)), id=\(eventHotkeyId.id) - Handler ID: \(hotkey.hotkeyId)")
        
        if eventHotkeyId.signature == OSType(UInt32(truncatingIfNeeded: hotkey.hotkeyType)) {
            return hotkey.action()
        }
        
        return noErr
    }
    
    @MainActor static var eventHandlerRef: EventHandlerRef? = nil
    
    static var hotkeys: [Int: GlobalHotkey] = [:]
    static var hotkeyIdI = 0
    
    @MainActor
    static func setup() {
        let status = InstallEventHandler(GetEventDispatcherTarget(),
                                         Self.handler,
                                         1,
                                         [EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                                        eventKind: UInt32(kEventHotKeyPressed))],
                                         nil,
                                         &eventHandlerRef)
        
        if status != noErr {
            debugLog("Failed to install global event handler: \(status)")
        } else {
            debugLog("Successfully installed global event handler")
        }

        // Hotkeys are registered by key code, so the key a shortcut lives on moves
        // when the keyboard layout changes. Register them again on the new layout.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                           object: nil,
                                                           queue: .main) { _ in
            Task { @MainActor in
                Self.reregisterAll()
            }
        }
    }

    @MainActor
    static func reregisterAll() {
        let registeredHotkeys = Array(hotkeys.values)

        guard !registeredHotkeys.isEmpty else { return }

        debugLog("Keyboard input source changed, re-registering \(registeredHotkeys.count) hotkey(s)")

        for hotkey in registeredHotkeys {
            hotkey.register()
        }
    }

    var shortcut: String?
    var action: (() -> OSStatus)
    
    @MainActor var hotKeyRef: EventHotKeyRef?
    
    let hotkeyType = "MYZS".utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    
    var hotkeyId: UInt32
    var eventHotkeyId: EventHotKeyID?
    
    var id: Int { Int(hotkeyId) }
    
    init(shortcut: String? = nil, action: @escaping (() -> OSStatus)) {
        self.shortcut = shortcut
        self.action = action
        
        Self.hotkeyIdI += 1
        hotkeyId = UInt32(Self.hotkeyIdI)
    }
    
    static func == (lhs: GlobalHotkey, rhs: GlobalHotkey) -> Bool {
        return lhs.id == rhs.id
    }

    @MainActor
    func register(for shortcut: String? = nil) {
        guard let newShortcut = shortcut ?? self.shortcut else {
            debugLog("No shortcut provided for registration")
            return
        }
        
        self.shortcut = newShortcut
        
        if newShortcut.isEmpty {
            unregister()
            debugLog("Shortcut is empty, unregistered and skipping registration")
            return
        }
        
        if let existingHotKeyRef = hotKeyRef {
            let unregisterStatus = UnregisterEventHotKey(existingHotKeyRef)
            debugLog("Unregistered old hotkey with status: \(unregisterStatus)")
            hotKeyRef = nil
        }
        
        let parsed = Self.parseShortcut(newShortcut)
        
        guard let parsedKeyCode = parsed.keyCode else {
            debugLog("Invalid key in shortcut: \(newShortcut)")
            return
        }
        
        var modifiers: UInt32 = 0
        if parsed.modifiers.contains(NSEvent.ModifierFlags.command) {
            modifiers |= UInt32(cmdKey)
        }
        if parsed.modifiers.contains(NSEvent.ModifierFlags.option) {
            modifiers |= UInt32(optionKey)
        }
        if parsed.modifiers.contains(NSEvent.ModifierFlags.control) {
            modifiers |= UInt32(controlKey)
        }
        if parsed.modifiers.contains(NSEvent.ModifierFlags.shift) {
            modifiers |= UInt32(shiftKey)
        }
        
        let keyCode = UInt32(parsedKeyCode)
        
        eventHotkeyId = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: hotkeyType)), id: hotkeyId)
        let status = RegisterEventHotKey(keyCode, modifiers, eventHotkeyId!, GetEventDispatcherTarget(), 0, &hotKeyRef)
        
        if status == noErr {
            Self.hotkeys[id] = self
            debugLog("Successfully registered hotkey: \(newShortcut)")
        } else {
            debugLog("Failed to register hotkey: \(status)")
        }
    }

    @MainActor
    func unregister() {
        if let hotKeyRef {
            let status = UnregisterEventHotKey(hotKeyRef)
            debugLog("Unregistered hotkey with status: \(status)")
            Self.hotkeys.removeValue(forKey: id)
        } else {
            debugLog("No hotkey to unregister")
        }
    }

    @MainActor
    func refresh() {
        debugLog("Refreshing global hotkey...")
        
        unregister()
        
        guard let shortcut = self.shortcut else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.register(for: shortcut)
        }
    }
    
    static func parseShortcut(_ shortcut: String) -> (modifiers: NSEvent.ModifierFlags, keyCode: UInt16?, key: String?) {
        let components = shortcut.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var modifiers: NSEvent.ModifierFlags = []
        var keyCode: UInt16?
        var key: String?
        
        for component in components {
            switch component.lowercased() {
                case "command", "cmd":
                    modifiers.insert(.command)
                case "option", "alt":
                    modifiers.insert(.option)
                case "control", "ctrl":
                    modifiers.insert(.control)
                case "shift":
                    modifiers.insert(.shift)
                case "tab":
                    keyCode = 48
                    key = "tab"
                case "return", "enter":
                    keyCode = 36
                    key = "return"
                case "delete", "backspace":
                    keyCode = 51
                    key = "delete"
                case "escape", "esc":
                    keyCode = 53
                    key = "escape"
                case "space":
                    keyCode = 49
                    key = "space"
                case "left":
                    keyCode = 123
                    key = "left"
                case "right":
                    keyCode = 124
                    key = "right"
                case "down":
                    keyCode = 125
                    key = "down"
                case "up":
                    keyCode = 126
                    key = "up"
                default:
                    if component.count == 1 {
                        let char = component.uppercased()
                        key = char
                        keyCode = keyCodeForCharacter(char)
                    }
            }
        }
        
        return (modifiers, keyCode, key)
    }

    static let qwertyKeyCodes: [Character: UInt16] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
        "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,

        "q": 12, "w": 13, "e": 14, "r": 15, "t": 17,
        "y": 16, "u": 32, "i": 34, "o": 31, "p": 35,

        "a": 0, "s": 1, "d": 2, "f": 3, "g": 5,
        "h": 4, "j": 38, "k": 40, "l": 37,

        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "n": 45, "m": 46,

        "-": 27, "=": 24,
        "[": 33, "]": 30,
        "\\": 42, ";": 41, "'": 39,
        ",": 43, ".": 47, "/": 44,
        "`": 50
    ]

    // A layout can type the same character on a main block key and on the keypad,
    // and the keypad is never the one the user pressed. French types 1 there.
    static let keypadKeyCodes: Set<UInt16> = Set([kVK_ANSI_KeypadDecimal,
                                                  kVK_ANSI_KeypadMultiply,
                                                  kVK_ANSI_KeypadPlus,
                                                  kVK_ANSI_KeypadClear,
                                                  kVK_ANSI_KeypadDivide,
                                                  kVK_ANSI_KeypadEnter,
                                                  kVK_ANSI_KeypadMinus,
                                                  kVK_ANSI_KeypadEquals,
                                                  kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2,
                                                  kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
                                                  kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8,
                                                  kVK_ANSI_Keypad9].map { UInt16($0) })

    static func keyCodeForCharacter(_ character: String) -> UInt16? {
        guard let char = character.lowercased().first else { return nil }

        if let keyCode = keyCodeForCharacter(char, in: currentKeyboardLayoutData()) {
            return keyCode
        }

        return qwertyKeyCodes[char]
    }

    static func currentKeyboardLayoutData() -> CFData? {
        // An input method (Pinyin, Kotoeri, ...) carries no key layout data of its own,
        // so fall back to the ASCII capable layout its keys really type with.
        let inputSources = [TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()]

        for inputSource in inputSources.compactMap({ $0 }) {
            if let layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) {
                return unsafeBitCast(layoutData, to: CFData.self)
            }
        }

        return nil
    }

    static func keyCodeForCharacter(_ character: Character, in layoutData: CFData?) -> UInt16? {
        guard let layoutData else { return nil }
        guard let keyLayout = CFDataGetBytePtr(layoutData) else { return nil }

        let charString = String(character).lowercased()

        for virtualKeyCode in UInt16(0)..<128 where !keypadKeyCodes.contains(virtualKeyCode) {
            var deadKeyState: UInt32 = 0
            var actualStringLength = 0
            var unicodeString = [UniChar](repeating: 0, count: 4)

            let result = UCKeyTranslate(keyLayout.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { $0 },
                                        virtualKeyCode,
                                        UInt16(kUCKeyActionDisplay),
                                        0,
                                        UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeyState,
                                        4,
                                        &actualStringLength,
                                        &unicodeString)

            if result == noErr && actualStringLength > 0 {
                let resultString = String(utf16CodeUnits: unicodeString, count: actualStringLength)
                if resultString.lowercased() == charString {
                    return virtualKeyCode
                }
            }
        }

        return nil
    }
}
