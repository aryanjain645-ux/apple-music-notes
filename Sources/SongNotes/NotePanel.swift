import AppKit
import SwiftUI

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class NotePanelController {
    private var panel: KeyPanel?

    func show(track: Track?) {
        close()
        let host = NSHostingView(rootView: NoteView(track: track, onClose: { [weak self] in self?.close() }))
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 180),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.contentView = host
        p.setContentSize(host.fittingSize)
        p.center()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

struct NoteView: View {
    let track: Track?        // captured when the panel opened, so a song change mid-typing can't misfile the note
    let onClose: () -> Void

    @State private var text = ""
    @State private var usedVoice = false
    @StateObject private var dictation = Dictation()
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let t = track {
                HStack(spacing: 8) {
                    Image(systemName: "music.note").foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.headline).lineLimit(1)
                        Text(t.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if !t.inLibrary {
                    Text("This song isn't in your library. The note is still saved, but add the song in Music so its tags show there and it can go into playlists.")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Nothing is playing in Music").font(.headline)
            }

            HStack(alignment: .top, spacing: 8) {
                TextField("Your thoughts… e.g. perfect sunset song, slow build", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .lineLimit(2...6)
                    .focused($focused)
                    .onSubmit(save)
                Button {
                    dictation.toggle(base: text) { text = $0; usedVoice = true }
                } label: {
                    Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(dictation.isRecording ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Speak your note (click again to stop)")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))

            if let e = dictation.error {
                Text(e).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("⏎ save   esc close").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(track == nil || trimmed.isEmpty)
            }
        }
        .padding(16)
        .padding(.top, 6)
        .frame(width: 460)
        .onAppear { focused = true }
        .onExitCommand { dictation.stop(); onClose() }
    }

    private func save() {
        dictation.stop()
        guard let t = track, !trimmed.isEmpty else { return }
        AppModel.shared.save(text: trimmed, source: usedVoice ? "voice" : "typed", track: t)
        onClose()
    }
}
