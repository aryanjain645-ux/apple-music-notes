import AppKit
import SwiftUI

@MainActor
enum SetupWindow {
    private static var window: NSWindow?

    static func show() {
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = EditingWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "SongNotes Settings"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SetupView(initial: AppModel.shared.config) { w.close() })
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct SetupView: View {
    @State var config: Config
    @State private var error: String?
    let onDone: () -> Void

    init(initial: Config, onDone: @escaping () -> Void) {
        _config = State(initialValue: initial)
        self.onDone = onDone
    }

    var body: some View {
        Form {
            Section {
                TextField("Supabase project URL", text: $config.supabaseURL, prompt: Text("https://xxxx.supabase.co"))
                SecureField("Supabase secret key", text: $config.supabaseKey, prompt: Text("sb_secret_… or service_role key"))
            } header: { Text("Supabase (where your notes live)") }
            Section {
                SecureField("Gemini API key", text: Binding(get: { config.geminiKey ?? "" }, set: { config.geminiKey = $0 }),
                            prompt: Text("Used if set"))
                SecureField("Anthropic API key", text: $config.anthropicKey, prompt: Text("Optional: used if no Gemini key"))
                TextField("Model", text: Binding(get: { config.model ?? "" }, set: { config.model = $0 }),
                          prompt: Text(config.provider == .gemini ? "gemini-flash-latest" : "claude-opus-5-5"))
            } header: { Text("AI tagging (turns notes into tags)") }
            Text("Saved to ~/.config/songnotes/config.json, readable only by you. Shortcut to add a note: ⌃⌥N")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Save") {
                    config.supabaseURL = config.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    config.supabaseKey = config.supabaseKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    config.anthropicKey = config.anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    config.geminiKey = config.geminiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                    do {
                        try config.save()
                        AppModel.shared.configChanged(config)
                        onDone()
                    } catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
    }
}
