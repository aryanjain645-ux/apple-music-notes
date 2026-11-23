import AppKit
import Foundation

/// A note waiting to reach Supabase (survives offline / restarts).
struct QueuedNote: Codable {
    var id = UUID()
    var track: Track
    var text: String
    var source: String
    var createdAt: Date
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var config = Config.load()
    @Published var current: Track?
    @Published var tagCounts: [TagCount] = []
    @Published var recent: [RecentNote] = []
    @Published var status: String?

    private var hotkey: Hotkey?
    private var timer: Timer?
    private var syncing = false
    /// Set after a 429/5xx from the tagger so we don't spend the (tiny) free quota retrying.
    private var taggingPausedUntil: Date?
    let panel = NotePanelController()

    private static let queueFile = Config.dir.appendingPathComponent("queue.json")

    var store: SupabaseStore? {
        config.isComplete ? SupabaseStore(baseURL: config.supabaseURL, key: config.supabaseKey) : nil
    }
    var tagger: Tagger? {
        config.isComplete ? Tagger(provider: config.provider, apiKey: config.taggerKey, model: config.modelID) : nil
    }

    func start() {
        hotkey = Hotkey { [weak self] in self?.openNote() }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppModel.shared.refreshNowPlaying() }
        }
        refreshNowPlaying()
        if config.isComplete {
            Task { await sync() }
        } else {
            SetupWindow.show()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in await AppModel.shared.sync() }
        }
    }

    private var pauseReason = ""

    /// 429: wait as long as Google says (its RetryInfo "retryDelay": "12307s"), else an hour.
    /// 5xx: wait 15 minutes.
    private func pauseTagging(code: Int, body: String) {
        var seconds: Double = code == 429 ? 3600 : 900
        if code == 429,
           let r = body.range(of: #""retryDelay":\s*"([0-9.]+)s""#, options: .regularExpression) {
            let digits = body[r].filter { "0123456789.".contains($0) }
            if let d = Double(digits) { seconds = d + 60 }
        }
        pauseReason = code == 429 ? "AI quota used up" : "AI service busy"
        taggingPausedUntil = Date().addingTimeInterval(seconds)
    }

    func refreshNowPlaying() {
        do {
            current = try MusicBridge.nowPlaying()
            if status?.hasPrefix("Can't read Music") == true { status = nil }
        } catch {
            current = nil
            status = "Can't read Music: \(error.localizedDescription). Allow SongNotes under System Settings › Privacy & Security › Automation."
        }
    }

    func openNote() {
        refreshNowPlaying()
        if !config.isComplete { SetupWindow.show(); return }
        panel.show(track: current)
    }

    func configChanged(_ c: Config) {
        config = c
        taggingPausedUntil = nil
        Task { await sync() }
    }

    // MARK: Saving

    func save(text: String, source: String, track: Track) {
        var q = loadQueue()
        q.append(QueuedNote(track: track, text: text, source: source, createdAt: Date()))
        saveQueue(q)
        status = "Saved note on \(track.title)"
        Task { await sync() }
    }

    private var needsResync = false

    /// Push queued notes, tag anything pending, refresh menus. Re-runs if a save lands mid-sync.
    func sync() async {
        guard store != nil else { return }
        if syncing { needsResync = true; return }
        syncing = true
        repeat {
            needsResync = false
            await syncOnce()
        } while needsResync
        syncing = false
    }

    private func syncOnce() async {
        guard let store else { return }

        // 1. Flush the offline queue. Re-read the file each time so notes saved meanwhile are never overwritten.
        while let n = loadQueue().first {
            do {
                try await store.upsertTrack(n.track)
                _ = try await store.insertNote(persistentID: n.track.persistentID, text: n.text,
                                               source: n.source, createdAt: n.createdAt)
                var q = loadQueue()
                q.removeAll { $0.id == n.id }
                saveQueue(q)
            } catch {
                status = "Sync failed (\(loadQueue().count) waiting): \(error.localizedDescription)"
                return
            }
        }

        // 2. Tag pending notes.
        if let until = taggingPausedUntil, until > Date() {
            status = "AI tagging paused until \(until.formatted(date: .omitted, time: .shortened)) (\(pauseReason)). Notes are saved."
        } else if let tagger {
            taggingPausedUntil = nil
            let vocab = (try? await store.tagCounts())?.map(\.label) ?? tagCounts.map(\.label)
            var vocabulary = Array(Set(vocab)).sorted()
            for p in (try? await store.pendingNotes()) ?? [] {
                do {
                    let tags = try await tagger.tag(note: p.raw_text, title: p.tracks?.title ?? "",
                                                    artist: p.tracks?.artist, album: p.tracks?.album,
                                                    genre: p.tracks?.genre, bpm: p.tracks?.bpm,
                                                    vocabulary: vocabulary)
                    try await store.applyTags(noteID: p.id, tags)
                    vocabulary = Array(Set(vocabulary + tags.vibes + tags.tags)).sorted()
                    await mirror(persistentID: p.persistent_id)
                    status = "Tagged \(p.tracks?.title ?? "note"): \(tags.commentLine)"
                } catch let e as Tagger.TagError {
                    if case .http(let code, let body) = e, code == 429 || code >= 500 {
                        pauseTagging(code: code, body: body)
                        status = "AI tagging paused until \(taggingPausedUntil!.formatted(date: .omitted, time: .shortened)) (\(pauseReason)). Notes are saved."
                        break
                    }
                    try? await store.markTagFailed(noteID: p.id)
                    status = e.localizedDescription
                } catch {
                    status = error.localizedDescription
                    break
                }
            }
        }

        // 3. Refresh menus.
        if let counts = try? await store.tagCounts() {
            var best: [String: TagCount] = [:]
            for c in counts where (best[c.label]?.songs ?? 0) < c.songs { best[c.label] = c }
            tagCounts = best.values.sorted { ($0.songs, $1.label) > ($1.songs, $0.label) }
        }
        if let r = try? await store.recentNotes() { recent = r }
    }

    /// Mirror the song's merged tags (from every note on it) into Music's Comments.
    private func mirror(persistentID: String) async {
        guard let store, let p = try? await store.profile(persistentID: persistentID) else { return }
        do {
            try MusicBridge.mirrorTags(persistentID: persistentID, tagLine: p.commentLine)
        } catch {
            // Not in library, or Music refused. Supabase stays the source of truth.
        }
    }

    // MARK: Playlists

    func makePlaylist(label: String) {
        guard let store else { return }
        Task {
            do {
                let rows = try await store.tracks(withLabel: label)
                guard !rows.isEmpty else { status = "No songs tagged \(label)"; return }
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                let name = "SongNotes · \(label) · \(df.string(from: Date()))"
                let (added, skipped) = try MusicBridge.createPlaylist(
                    name: name, tracks: rows.map { ($0.persistent_id, $0.title, $0.artist ?? "") })
                status = "Created “\(name)”: \(added) songs" + (skipped > 0 ? ", \(skipped) not in library" : "")
            } catch {
                status = "Playlist failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Queue file

    private func loadQueue() -> [QueuedNote] {
        guard let d = try? Data(contentsOf: Self.queueFile) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([QueuedNote].self, from: d)) ?? []
    }

    private func saveQueue(_ q: [QueuedNote]) {
        try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(q).write(to: Self.queueFile, options: .atomic)
    }
}
