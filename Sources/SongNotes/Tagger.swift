import Foundation

/// Turns a free-text note into structured tags with Gemini (default) or Claude, using JSON-schema output.
struct Tagger {
    enum Provider { case gemini, anthropic }
    let provider: Provider
    let apiKey: String
    let model: String

    enum TagError: LocalizedError {
        case http(Int, String), refusal, noText
        var errorDescription: String? {
            switch self {
            case .http(let c, let b): return "Tagging API \(c): \(b.prefix(200))"
            case .refusal: return "The AI declined to tag this note."
            case .noText: return "The AI returned no tags."
            }
        }
    }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "vibes": ["type": "array", "items": ["type": "string"],
                      "description": "Mood, time of day or setting, e.g. sunset, sunrise, late-night, beach, driving, rainy."],
            "energy": ["type": "integer", "description": "1 = ambient/chill, 3 = groove, 5 = peak-time banger."],
            "set_role": ["type": "string", "enum": ["opener", "warmup", "build", "peak", "cooldown", "closer", "none"]],
            "tags": ["type": "array", "items": ["type": "string"],
                     "description": "Anything else useful for picking songs: vocal, instrumental, slow-build, crowd-pleaser, transition-friendly, etc."],
            "summary": ["type": "string", "description": "The note restated in at most 12 words."],
        ],
        "required": ["vibes", "energy", "set_role", "tags", "summary"],
        "additionalProperties": false,
    ]

    func tag(note: String, title: String, artist: String?, album: String?, genre: String?, bpm: Int?,
             vocabulary: [String]) async throws -> NoteTags {
        let system = """
        You turn a DJ's quick, informal note about a song into tags they will later filter on to build playlists.
        Rules:
        - Every vibe and tag is lowercase, one or two words joined by a hyphen (e.g. "sunset", "slow-build").
        - Reuse a label from the existing vocabulary whenever it means the same thing; only invent a new one when nothing fits.
        - Only tag what the note says or clearly implies. Use the song's genre/BPM only to estimate energy when the note doesn't say.
        - set_role is "none" unless the note suggests where in a set the song belongs.
        Existing vocabulary: \(vocabulary.isEmpty ? "(none yet)" : vocabulary.joined(separator: ", "))
        """
        var meta = "Song: \(title)"
        if let artist, !artist.isEmpty { meta += " — \(artist)" }
        if let album, !album.isEmpty { meta += "\nAlbum: \(album)" }
        if let genre, !genre.isEmpty { meta += "\nGenre: \(genre)" }
        if let bpm, bpm > 0 { meta += "\nBPM: \(bpm)" }
        let user = "\(meta)\n\nMy note: \(note)"

        let text: String
        switch provider {
        case .gemini: text = try await callGemini(system: system, user: user)
        case .anthropic: text = try await callAnthropic(system: system, user: user)
        }
        var tags = try JSONDecoder().decode(NoteTags.self, from: Data(Tagger.stripFences(text).utf8))
        tags.vibes = Tagger.clean(tags.vibes)
        tags.tags = Tagger.clean(tags.tags).filter { !tags.vibes.contains($0) }
        tags.energy = min(5, max(1, tags.energy))
        return tags
    }

    static func clean(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        return labels.compactMap { raw in
            let s = raw.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            guard !s.isEmpty, seen.insert(s).inserted else { return nil }
            return s
        }
    }

    static func stripFences(_ t: String) -> String {
        var s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.drop { $0 != "\n" }.dropFirst().description
            if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        }
        return s
    }

    // MARK: Gemini

    private func callGemini(system: String, user: String) async throws -> String {
        func body(_ jsonSchema: Bool) -> [String: Any] {
            var gen: [String: Any] = ["responseMimeType": "application/json"]
            if jsonSchema {
                gen["responseJsonSchema"] = Tagger.schema
            } else {
                var legacy = Tagger.schema
                legacy.removeValue(forKey: "additionalProperties")
                gen["responseSchema"] = legacy
            }
            return [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": user]]]],
                "generationConfig": gen,
            ]
        }
        let data: Data
        do {
            data = try await postGemini(body(true))
        } catch TagError.http(400, let msg) where msg.lowercased().contains("schema") {
            data = try await postGemini(body(false))
        }
        struct Part: Codable { var text: String?; var thought: Bool? }
        struct Content: Codable { var parts: [Part]? }
        struct Cand: Codable { var content: Content?; var finishReason: String? }
        struct Resp: Codable { var candidates: [Cand]? }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        guard let cand = resp.candidates?.first else { throw TagError.refusal }
        if ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST"].contains(cand.finishReason ?? "") { throw TagError.refusal }
        let text = (cand.content?.parts ?? []).filter { $0.thought != true }.compactMap(\.text).joined()
        guard !text.isEmpty else { throw TagError.noText }
        return text
    }

    /// Retries once when Google says the model is overloaded (503). A 429 (quota) is thrown straight away:
    /// the free tier allows only ~20 requests a day, so retrying would just burn it.
    private func postGemini(_ body: [String: Any]) async throws -> Data {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var lastError: Error = TagError.noText
        for attempt in 0..<2 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 60
            req.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 { return data }
            lastError = TagError.http(code, String(decoding: data, as: UTF8.self))
            guard code == 503, attempt == 0 else { break }
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
        throw lastError
    }

    // MARK: Claude

    private func callAnthropic(system: String, user: String) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": system,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": Tagger.schema]],
            "messages": [["role": "user", "content": user]],
            "fallbacks": "default",
        ]
        let data: Data
        do {
            data = try await postAnthropic(body, beta: "server-side-fallback-2026-07-01")
        } catch TagError.http(400, let msg) where msg.contains("fallback") {
            body.removeValue(forKey: "fallbacks")
            data = try await postAnthropic(body, beta: nil)
        }
        struct Block: Codable { var type: String; var text: String? }
        struct Resp: Codable { var stop_reason: String?; var content: [Block] }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        if resp.stop_reason == "refusal" { throw TagError.refusal }
        guard let text = resp.content.first(where: { $0.type == "text" })?.text else { throw TagError.noText }
        return text
    }

    private func postAnthropic(_ body: [String: Any], beta: String?) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let beta { req.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw TagError.http(code, String(decoding: data, as: UTF8.self)) }
        return data
    }
}
