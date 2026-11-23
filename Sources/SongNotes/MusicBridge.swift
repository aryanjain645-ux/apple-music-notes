import Foundation

struct Track: Codable, Equatable {
    var persistentID: String
    var title: String
    var artist: String
    var album: String
    var durationS: Int?
    var bpm: Int?
    var genre: String
    var inLibrary: Bool
}

enum MusicError: LocalizedError {
    case script(String)
    var errorDescription: String? {
        if case .script(let m) = self { return m }
        return nil
    }
}

/// Talks to the Music app through AppleScript. Call from the main thread.
enum MusicBridge {
    static let commentStart = "[sn]"
    static let commentEnd = "[/sn]"

    @discardableResult
    private static func run(_ source: String) throws -> NSAppleEventDescriptor {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw MusicError.script("Bad script") }
        let result = script.executeAndReturnError(&err)
        if let err {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            throw MusicError.script(msg)
        }
        return result
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The song currently loaded in Music, or nil if Music isn't running / nothing is playing.
    static func nowPlaying() throws -> Track? {
        let src = """
        if application "Music" is not running then return {}
        tell application "Music"
          if player state is stopped then return {}
          try
            set t to current track
          on error
            return {}
          end try
          set pid to persistent ID of t
          set d to "" & 0
          try
            set d to (round (duration of t)) as text
          on error
            try
              set d to (round (duration of (first track of library playlist 1 whose persistent ID is pid))) as text
            end try
          end try
          set b to "0"
          try
            set b to (bpm of t) as text
          end try
          set g to ""
          try
            set g to (genre of t) as text
          end try
          set al to ""
          try
            set al to (album of t) as text
          end try
          set ar to ""
          try
            set ar to (artist of t) as text
          end try
          set inLib to "0"
          try
            if exists (some track of library playlist 1 whose persistent ID is pid) then set inLib to "1"
          end try
          return {pid, (name of t) as text, ar, al, d, b, g, inLib}
        end tell
        """
        let d = try run(src)
        guard d.numberOfItems >= 8 else { return nil }
        func s(_ i: Int) -> String { d.atIndex(i)?.stringValue ?? "" }
        let dur = Int(s(5)) ?? 0
        let bpm = Int(s(6)) ?? 0
        return Track(persistentID: s(1), title: s(2), artist: s(3), album: s(4),
                     durationS: dur > 0 ? dur : nil, bpm: bpm > 0 ? bpm : nil,
                     genre: s(7), inLibrary: s(8) == "1")
    }

    /// Writes "[sn] #sunset #e2 … [/sn]" into the track's Comments, keeping any other comment text.
    static func mirrorTags(persistentID: String, tagLine: String) throws {
        let pid = esc(persistentID)
        let read = try run("""
        tell application "Music" to get comment of (first track of library playlist 1 whose persistent ID is "\(pid)")
        """)
        let existing = read.stringValue ?? ""
        let merged = mergeComment(existing: existing, tagLine: tagLine)
        try run("""
        tell application "Music" to set comment of (first track of library playlist 1 whose persistent ID is "\(pid)") to "\(esc(merged))"
        """)
    }

    static func mergeComment(existing: String, tagLine: String) -> String {
        var base = existing
        if let s = base.range(of: commentStart),
           let e = base.range(of: commentEnd, range: s.upperBound..<base.endIndex) {
            base.removeSubrange(s.lowerBound..<e.upperBound)
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = "\(commentStart) \(tagLine) \(commentEnd)"
        return base.isEmpty ? block : "\(base)\n\(block)"
    }

    /// Creates a playlist. Matches by persistent ID, falling back to title + artist
    /// (for songs noted before they were added to the library). Returns (added, skipped).
    static func createPlaylist(name: String, tracks: [(id: String, title: String, artist: String)]) throws -> (Int, Int) {
        let items = tracks.map { "{\"\(esc($0.id))\", \"\(esc($0.title))\", \"\(esc($0.artist))\"}" }
            .joined(separator: ", ")
        let src = """
        tell application "Music"
          set p to make new user playlist with properties {name:"\(esc(name))"}
          set added to 0
          set skipped to 0
          repeat with it in {\(items)}
            set ok to false
            try
              duplicate (first track of library playlist 1 whose persistent ID is (item 1 of it)) to p
              set ok to true
            end try
            if not ok then
              try
                duplicate (first track of library playlist 1 whose name is (item 2 of it) and artist is (item 3 of it)) to p
                set ok to true
              end try
            end if
            if ok then
              set added to added + 1
            else
              set skipped to skipped + 1
            end if
          end repeat
          return {added, skipped}
        end tell
        """
        let d = try run(src)
        return (Int(d.atIndex(1)?.int32Value ?? 0), Int(d.atIndex(2)?.int32Value ?? 0))
    }
}
