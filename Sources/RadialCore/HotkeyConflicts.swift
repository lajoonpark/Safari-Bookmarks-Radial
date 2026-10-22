import Foundation

/// Well-known shortcuts that a global hotkey would shadow.
///
/// A Carbon hot key is delivered before the frontmost app sees the key, so registering ⌘R
/// stops ⌘R from reloading Safari. That is a real trade-off rather than a bug, so it is
/// surfaced instead of hidden.
public enum HotkeyConflicts {

    public struct Conflict: Equatable {
        public let owner: String
        public let description: String
    }

    private struct Rule {
        let keyCode: UInt32
        let command: Bool
        let option: Bool
        let control: Bool
        let shift: Bool
        let owner: String
        let description: String
    }

    // Only combinations that are genuinely disruptive in a browser get flagged.
    private static let rules: [Rule] = [
        Rule(keyCode: 15, command: true, option: false, control: false, shift: false,
             owner: "Safari", description: "reloads the page"),
        Rule(keyCode: 1, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "saves"),
        Rule(keyCode: 17, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "opens a new tab"),
        Rule(keyCode: 13, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "closes the window"),
        Rule(keyCode: 6, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "undoes"),
        Rule(keyCode: 35, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "prints"),
        Rule(keyCode: 31, command: true, option: false, control: false, shift: false,
             owner: "Most apps", description: "opens a file"),
    ]

    public static func conflict(for spec: HotkeySpec) -> Conflict? {
        guard spec.isValid else { return nil }
        for rule in rules {
            if rule.keyCode == spec.keyCode,
               rule.command == spec.command,
               rule.option == spec.option,
               rule.control == spec.control,
               rule.shift == spec.shift {
                return Conflict(owner: rule.owner, description: rule.description)
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
