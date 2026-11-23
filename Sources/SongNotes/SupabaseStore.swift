import Foundation

struct TagCount: Codable, Identifiable, Hashable {
    var label: String
    var kind: String
    var songs: Int
    var id: String { kind + ":" + label }
}

struct RecentNote: Codable, Identifiable {
    struct T: Codable { var title: String; var artist: String? }
    var id: String
    var raw_text: String
    var tracks: T?
}

struct NoteTags: Codable {
    var vibes: [String]
    var energy: Int
    var set_role: String
    var tags: [String]
    var summary: String

    /// "#sunset #e2 #opener #slow-build"
    var commentLine: String {
        var parts = vibes.map { "#\($0)" }
        parts.append("#e\(energy)")
        if set_role != "none" { parts.append("#\(set_role)") }
        parts += tags.map { "#\($0)" }
        return parts.joined(separator: " ")
    }
}

/// Supabase over plain HTTPS (PostgREST). No SDK.
struct SupabaseStore {
    let baseURL: String
    let key: String

    enum StoreError: LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            if case .http(let c, let b) = self { return "Supabase \(c): \(b.prefix(200))" }
            return nil
        }
    }

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [],
                         body: Any? = nil, prefer: String? = nil) async throws -> Data {
        var comps = URLComponents(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/rest/v1/" + path)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue(key, forHTTPHeaderField: "apikey")
        if key.hasPrefix("eyJ") { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") } // legacy JWT keys
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw StoreError.http(code, String(decoding: data, as: UTF8.self)) }
        return data
    }

    func upsertTrack(_ t: Track) async throws {
        var row: [String: Any] = ["persistent_id": t.persistentID, "title": t.title, "artist": t.artist,
                                  "album": t.album, "genre": t.genre, "in_library": t.inLibrary]
        if let d = t.durationS { row["duration_s"] = d }
        if let b = t.bpm { row["bpm"] = b }
        _ = try await request("POST", "tracks", query: [.init(name: "on_conflict", value: "persistent_id")],
                              body: [row], prefer: "resolution=merge-duplicates,return=minimal")
    }

    /// Returns the new note's id.
    func insertNote(persistentID: String, text: String, source: String, createdAt: Date) async throws -> String {
        let row: [String: Any] = ["persistent_id": persistentID, "raw_text": text, "source": source,
                                  "created_at": ISO8601DateFormatter().string(from: createdAt)]
        let data = try await request("POST", "notes", query: [.init(name: "select", value: "id")],
                                     body: [row], prefer: "return=representation")
        struct R: Codable { var id: String }
        return try JSONDecoder().decode([R].self, from: data).first?.id ?? ""
    }

    func applyTags(noteID: String, _ tags: NoteTags) async throws {
        let body: [String: Any] = ["vibes": tags.vibes, "energy": tags.energy, "set_role": tags.set_role,
                                   "tags": tags.tags, "ai_summary": tags.summary, "tag_status": "done"]
        _ = try await request("PATCH", "notes", query: [.init(name: "id", value: "eq.\(noteID)")],
                              body: body, prefer: "return=minimal")
    }

    func markTagFailed(noteID: String) async throws {
        _ = try await request("PATCH", "notes", query: [.init(name: "id", value: "eq.\(noteID)")],
                              body: ["tag_status": "failed"], prefer: "return=minimal")
    }

    func tagCounts() async throws -> [TagCount] {
        let data = try await request("GET", "tag_counts", query: [.init(name: "select", value: "*"),
                                                                   .init(name: "limit", value: "60")])
        return try JSONDecoder().decode([TagCount].self, from: data)
    }

    func recentNotes(limit: Int = 6) async throws -> [RecentNote] {
        let data = try await request("GET", "notes", query: [
            .init(name: "select", value: "id,raw_text,tracks(title,artist)"),
            .init(name: "order", value: "created_at.desc"),
            .init(name: "limit", value: String(limit)),
        ])
        return try JSONDecoder().decode([RecentNote].self, from: data)
    }

    struct ProfileRow: Codable { var persistent_id: String; var title: String; var artist: String?; var energy: Int? }

    /// Songs carrying a label (as a vibe, tag, or set role), gentlest first.
    func tracks(withLabel label: String) async throws -> [ProfileRow] {
        let l = label.replacingOccurrences(of: "\"", with: "")
        let data = try await request("GET", "track_profile", query: [
            .init(name: "select", value: "persistent_id,title,artist,energy"),
            .init(name: "or", value: "(vibes.cs.{\"\(l)\"},tags.cs.{\"\(l)\"},set_role.eq.\"\(l)\")"),
            .init(name: "order", value: "energy.asc.nullslast,last_noted_at.asc"),
        ])
        return try JSONDecoder().decode([ProfileRow].self, from: data)
    }

    struct FullProfile: Codable {
        var vibes: [String]
        var tags: [String]
        var energy: Int?
        var set_role: String?

        var commentLine: String {
            var parts = vibes.map { "#\($0)" }
            if let energy { parts.append("#e\(energy)") }
            if let set_role, set_role != "none" { parts.append("#\(set_role)") }
            parts += tags.filter { !vibes.contains($0) }.map { "#\($0)" }
            return parts.joined(separator: " ")
        }
    }

    /// The song's tags merged across all its notes.
    func profile(persistentID: String) async throws -> FullProfile? {
        let data = try await request("GET", "track_profile", query: [
            .init(name: "select", value: "vibes,tags,energy,set_role"),
            .init(name: "persistent_id", value: "eq.\(persistentID)"),
        ])
        return try JSONDecoder().decode([FullProfile].self, from: data).first
    }

    struct PendingNote: Codable {
        struct T: Codable { var title: String; var artist: String?; var album: String?; var genre: String?; var bpm: Int? }
        var id: String
        var persistent_id: String
        var raw_text: String
        var tracks: T?
    }

    func pendingNotes() async throws -> [PendingNote] {
        let data = try await request("GET", "notes", query: [
            .init(name: "select", value: "id,persistent_id,raw_text,tracks(title,artist,album,genre,bpm)"),
            .init(name: "tag_status", value: "eq.pending"),
            .init(name: "limit", value: "25"),
        ])
        return try JSONDecoder().decode([PendingNote].self, from: data)
    }
}
