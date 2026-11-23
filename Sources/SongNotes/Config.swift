import Foundation

/// Lives at ~/.config/songnotes/config.json (permissions 600). Never in code.
struct Config: Codable, Equatable {
    var supabaseURL: String = ""
    var supabaseKey: String = ""    // secret key, or publishable key if the anon RLS policies are installed
    var geminiKey: String? = nil    // preferred tagger (free tier)
    var anthropicKey: String = ""   // optional alternative tagger
    var model: String? = nil        // overrides the default model for whichever provider is used

    var hasTagger: Bool { !(geminiKey ?? "").isEmpty || !anthropicKey.isEmpty }
    var isComplete: Bool { !supabaseURL.isEmpty && !supabaseKey.isEmpty && hasTagger }

    var provider: Tagger.Provider { (geminiKey ?? "").isEmpty ? .anthropic : .gemini }
    var taggerKey: String { provider == .gemini ? (geminiKey ?? "") : anthropicKey }
    var modelID: String {
        if let model, !model.isEmpty { return model }
        return provider == .gemini ? "gemini-flash-latest" : "claude-opus-5-5"
    }

    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/songnotes", isDirectory: true)
    static let file = dir.appendingPathComponent("config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: file),
              let c = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return c
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Config.file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.file.path)
    }
}
