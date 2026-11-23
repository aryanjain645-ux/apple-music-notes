import AppKit
import SwiftUI

@main
struct SongNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: "music.note.list")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        MainActor.assumeIsolated { AppModel.shared.start() }
    }

    /// Menu bar apps have no visible menu, so ⌘V/⌘C/⌘X/⌘A/⌘Z don't reach text fields
    /// (that also breaks Wispr Flow, which pastes). A hidden Edit menu restores them.
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    private func short(_ s: String, _ n: Int = 60) -> String {
        s.count > n ? String(s.prefix(n - 1)) + "…" : s
    }

    var body: some View {
        if let t = model.current {
            Text(short("♪ \(t.title) — \(t.artist)"))
        } else {
            Text("Nothing playing in Music")
        }
        Button("Add note…") { model.openNote() }
            .keyboardShortcut("n", modifiers: [.control, .option])

        Divider()

        Menu("Make playlist") {
            if model.tagCounts.isEmpty {
                Text("No tags yet. Add a few notes first.")
            }
            ForEach(model.tagCounts) { tc in
                Button("\(tc.label)  (\(tc.songs))") { model.makePlaylist(label: tc.label) }
            }
        }
        Menu("Recent notes") {
            if model.recent.isEmpty { Text("None yet") }
            ForEach(model.recent) { n in
                Text(short("\(n.tracks?.title ?? "?"): \(n.raw_text)", 80))
            }
        }

        if let s = model.status {
            Divider()
            Text(short(s, 80))
        }

        Divider()
        Button("Sync now") { Task { await model.sync() } }
        Button("Settings…") { SetupWindow.show() }
        Button("Quit SongNotes") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
