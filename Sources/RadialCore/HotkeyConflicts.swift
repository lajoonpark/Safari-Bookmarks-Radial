import Foundation

/// Well-known shortcuts that a global hotkey would shadow.
///
/// A Carbon hot key is delivered before the frontmost app sees the key, so registering ⌘R
/// stops ⌘R from reloading Safari. That is a real trade-off rather than a bug, so it is
/// surfaced instead of hidden — but with a severity, because shadowing ⌘E's "Use Selection
/// for Find" is not the same as breaking Save everywhere.
public enum HotkeyConflicts {

    public enum Severity: String, Codable, Equatable {
        /// Costs the frontmost app a convenience. Worth mentioning, not worth alarming about.
        case minor
        /// Breaks something people press many times an hour.
        case major
    }

    public struct Conflict: Equatable {
        public let owner: String
        public let description: String
        public let severity: Severity

        public init(owner: String, description: String, severity: Severity) {
            self.owner = owner
            self.description = description
            self.severity = severity
        }
    }

    private struct Rule {
        let keyCode: UInt32
        let command: Bool
        let option: Bool
        let control: Bool
        let shift: Bool
        let owner: String
        let description: String
        let severity: Severity
    }

    // Only combinations that are genuinely disruptive in a browser get flagged.
    private static let rules: [Rule] = [
        Rule(keyCode: 14, command: true, option: false, control: false, shift: false,
             owner: "Safari", description: "puts the selection in the search field", severity: .minor),
        Rule(keyCode: 15, command: true, option: false, control: false, shift: false,
             owner: "Safari", description: "reloads the page", severity: .major),
        Rule(keyCode: 1, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "saves", severity: .major),
        Rule(keyCode: 17, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "opens a new tab", severity: .major),
        Rule(keyCode: 13, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "closes the window", severity: .major),
        Rule(keyCode: 6, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "undoes", severity: .major),
        Rule(keyCode: 35, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "prints", severity: .minor),
        Rule(keyCode: 31, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "opens a file", severity: .minor),
        Rule(keyCode: 45, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "creates something new", severity: .minor),
        Rule(keyCode: 46, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "minimises the window", severity: .minor),
    ]

    public static func conflict(for spec: HotkeySpec) -> Conflict? {
        guard spec.isValid else { return nil }
        for rule in rules {
            if rule.keyCode == spec.keyCode,
               rule.command == spec.command,
               rule.option == spec.option,
               rule.control == spec.control,
               rule.shift == spec.shift {
                return Conflict(owner: rule.owner, description: rule.description, severity: rule.severity)
            }
        }
        return nil
    }

    /// Suggestion offered when the chosen shortcut would shadow something important.
    public static func saferAlternative(to spec: HotkeySpec) -> HotkeySpec {
        // Adding ⌃ to a ⌘ combination is almost always free.
        if spec.command && !spec.control {
            var alternative = spec
            alternative.control = true
            return alternative
        }
        var alternative = spec
        alternative.option = true
        return alternative
    }
}
