// Secure Keyboard Entry: when any app turns it on (a password field, a terminal's
// "Secure Keyboard Entry" setting, a chat app's sign-in sheet), macOS hides keyboard
// events from every event tap on the system. MailKeys goes deaf until it's released,
// and the keys fall through to Mail as plain letters.
//
// This file holds the wording. main.swift finds out who holds secure input.

import Foundation

enum SecureInput {
    /// The status line for the menu bar and the settings sidebar, or nil when nothing holds secure input.
    static func status(holder: String?) -> String? {
        guard let holder else { return nil }
        return "Keyboard blocked by \(holder)"
    }

    /// A one-line hint that fits in the menu.
    static func menuHint(holder: String) -> String {
        "Click into \(holder) and close any password prompt, or quit it."
    }

    /// The full explanation for the settings window.
    static func explanation(holder: String) -> String {
        "\(holder) turned on Secure Keyboard Entry, which hides keys from MailKeys. Click into \(holder) and close any password prompt. Quitting \(holder) also clears it."
    }
}
