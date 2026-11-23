import AppKit

/// Menu bar apps have no Edit menu, so ⌘V/⌘C/⌘X/⌘A/⌘Z never reach text fields
/// (this also breaks Wispr Flow, which pastes). These windows handle the shortcuts themselves.
private func handleEditShortcut(_ event: NSEvent, from sender: Any) -> Bool {
    guard event.type == .keyDown, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let selector: Selector?
    switch (flags, key) {
    case (.command, "v"): selector = #selector(NSText.paste(_:))
    case (.command, "c"): selector = #selector(NSText.copy(_:))
    case (.command, "x"): selector = #selector(NSText.cut(_:))
    case (.command, "a"): selector = #selector(NSText.selectAll(_:))
    case (.command, "z"): selector = Selector(("undo:"))
    case ([.command, .shift], "z"): selector = Selector(("redo:"))
    default: selector = nil
    }
    guard let selector else { return false }
    return NSApp.sendAction(selector, to: nil, from: sender)
}

final class EditingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditShortcut(event, from: self) || super.performKeyEquivalent(with: event)
    }
}

final class EditingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditShortcut(event, from: self) || super.performKeyEquivalent(with: event)
    }
}
