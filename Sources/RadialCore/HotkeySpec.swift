import Foundation

/// A global keyboard shortcut, described independently of Carbon/AppKit.
public struct HotkeySpec: Codable, Equatable {
    /// Virtual key code (Carbon `kVK_*`). Default is `kVK_ANSI_R` (15).
    public var keyCode: UInt32
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(keyCode: UInt32, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    /// ⌘R, the requested default.
    public static let `default` = HotkeySpec(keyCode: 15, command: true)

    /// At least one of ⌘/⌃/⌥ is required, otherwise the shortcut would swallow plain typing.
    public var isValid: Bool { command || control || option }

    public var modifierCount: Int {
        [command, option, control, shift].filter { $0 }.count
    }

    /// Human readable form, e.g. "⌘R" or "⌃⌥Space".
    public var displayName: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text + HotkeySpec.keyName(for: keyCode)
    }

    public static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeys[keyCode] { return special }
        if let letter = letterKeys[keyCode] { return letter }
        if let digit = digitKeys[keyCode] { return digit }
        return "Key \(keyCode)"
    }

    private static let letterKeys: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
    ]

    private static let digitKeys: [UInt32: String] = [
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
    ]

    private static let specialKeys: [UInt32: String] = [
        49: "Space", 36: "↩", 48: "⇥", 53: "⎋", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// Common shortcuts people might want, offered in settings.
    public static let suggestions: [HotkeySpec] = [
        .default,
        HotkeySpec(keyCode: 15, control: true),
        HotkeySpec(keyCode: 15, option: true),
        HotkeySpec(keyCode: 49, command: true, option: true),
        HotkeySpec(keyCode: 11, command: true, option: true),
    ]
}
