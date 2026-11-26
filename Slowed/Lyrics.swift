import Foundation
import AVFoundation
import Combine

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double?   // seconds in song time; nil for unsynced lyrics
    let text: String
}

struct Lyrics: Equatable {
    var lines: [LyricLine]
    var synced: Bool
    var source: String

    var isEmpty: Bool { lines.isEmpty }
}

enum LRCParser {
    /// Parses LRC ("[mm:ss.xx]text"). Falls back to plain text lines when there are no timestamps.
    static func parse(_ raw: String, source: String) -> Lyrics? {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var offset: Double = 0
        var timed: [(Double, String)] = []
        var plain: [String] = []
        let stampRegex = try? NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]", options: [])
        let wordRegex = try? NSRegularExpression(pattern: "<\\d{1,3}:\\d{1,2}(?:[.:]\\d{1,3})?>", options: [])

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("[offset:") {
                let v = line.dropFirst(8).dropLast().trimmingCharacters(in: .whitespaces)
                offset = (Double(v) ?? 0) / 1000.0
                continue
            }
            let ns = line as NSString
            let matches = stampRegex?.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length)) ?? []
            if matches.isEmpty {
                // Metadata tags like [ar:...] are skipped; anything else is plain lyric text.
                if line.hasPrefix("[") && line.hasSuffix("]") && line.contains(":") { continue }
                plain.append(line)
                continue
            }
            // Text after the last leading timestamp
            var lastEnd = 0
            var stamps: [Double] = []
            for m in matches where m.range.location == lastEnd {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac: Double = 0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                stamps.append(min * 60 + sec + frac)
                lastEnd = m.range.location + m.range.length
            }
            var body = ns.substring(from: lastEnd)
            if let wr = wordRegex {
                body = wr.stringByReplacingMatches(in: body, options: [], range: NSRange(location: 0, length: (body as NSString).length), withTemplate: "")
            }
            body = body.trimmingCharacters(in: .whitespaces)
            for s in stamps { timed.append((max(0, s - offset), body)) }
        }

        if timed.count >= 2 {
            let sorted = timed.sorted { $0.0 < $1.0 }
            var lines: [LyricLine] = []
            for (i, item) in sorted.enumerated() {
                lines.append(LyricLine(id: i, time: item.0, text: item.1.isEmpty ? "♪" : item.1))
            }
            return Lyrics(lines: lines, synced: true, source: source)
        }
        if !plain.isEmpty {
            return Lyrics(lines: plain.enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) },
                          synced: false, source: source)
        }
        return nil
    }

    static func isSynced(_ raw: String) -> Bool {
        return raw.range(of: "\\[\\d{1,3}:\\d{1,2}", options: .regularExpression) != nil
    }
}

enum SYLTParser {
    /// ID3v2 SYLT frame body: enc, lang(3), timestamp format, content type, descriptor, then (text, uint32 time)*.
    static func parse(_ data: Data) -> Lyrics? {
        let b = [UInt8](data)
        guard b.count > 6 else { return nil }
        let enc = b[0]
        let tsFormat = b[4]
        guard tsFormat == 2 || tsFormat == 1 else { return nil }
        var i = 6
        func readString() -> String? {
            let wide = (enc == 1 || enc == 2)
            var end = i
            if wide {
                while end + 1 < b.count && !(b[end] == 0 && b[end + 1] == 0) { end += 2 }
                guard end + 1 < b.count else { return nil }
            } else {
                while end < b.count && b[end] != 0 { end += 1 }
                guard end < b.count else { return nil }
            }
            let slice = Data(b[i..<end])
            i = end + (wide ? 2 : 1)
            switch enc {
            case 1: return String(data: slice, encoding: .utf16)
            case 2: return String(data: slice, encoding: .utf16BigEndian)
            case 3: return String(data: slice, encoding: .utf8)
            default: return String(data: slice, encoding: .isoLatin1)
            }
        }
        _ = readString() // descriptor
        var lines: [LyricLine] = []
        while i < b.count {
            guard let text = readString(), i + 4 <= b.count else { break }
            let t = UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
            i += 4
            guard tsFormat == 2 else { continue } // only milliseconds are useful
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(LyricLine(id: lines.count, time: Double(t) / 1000.0, text: clean.isEmpty ? "♪" : clean))
        }
        guard lines.count >= 2 else { return nil }
        let sorted = lines.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
        return Lyrics(lines: sorted.enumerated().map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) },
                      synced: true, source: L("Etiquetas del archivo"))
    }
}

final class LyricsStore: ObservableObject {
    static let shared = LyricsStore()

    @Published private(set) var lyrics: Lyrics? = nil
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var trackID: UUID? = nil

    static let onlineKey = "lyricsOnline"
    static var onlineEnabled: Bool {
        UserDefaults.standard.object(forKey: onlineKey) as? Bool ?? true
    }

    private var generation = 0
    private var cache: [UUID: Lyrics] = [:]
    private var onlineMisses: Set<UUID> = []

    static var lyricsDir: URL {
        let url = Library.support.appendingPathComponent("Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func userLRCURL(for track: Track) -> URL { lyricsDir.appendingPathComponent(track.id.uuidString + ".lrc") }
    static func onlineURL(for track: Track) -> URL { lyricsDir.appendingPathComponent(track.id.uuidString + ".online.lrc") }

    func load(for track: Track?, force: Bool = false) {
        guard let track = track else {
            trackID = nil; lyrics = nil; isLoading = false
            return
        }
        if !force, trackID == track.id, lyrics != nil || isLoading { return }
        generation += 1
        let gen = generation
        trackID = track.id
        if !force, let cached = cache[track.id] {
            lyrics = cached
            isLoading = false
            return
        }
        lyrics = nil
        isLoading = true
        let allowOnline = LyricsStore.onlineEnabled && !onlineMisses.contains(track.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let local = LyricsStore.loadLocal(track)
            if let l = local, l.synced {
                self.finish(l, track: track, gen: gen)
                return
            }
            if allowOnline {
                LyricsStore.fetchOnline(track) { online in
                    if online == nil {
                        DispatchQueue.main.async { self.onlineMisses.insert(track.id) }
                    }
                    // Prefer online synced over local plain; otherwise whatever we have.
                    if let o = online, o.synced || local == nil {
                        self.finish(o, track: track, gen: gen)
                    } else {
                        self.finish(local, track: track, gen: gen)
                    }
                }
            } else {
                self.finish(local, track: track, gen: gen)
            }
        }
    }

    /// Called (from any thread) when a sidecar .lrc lands in Documents.
    func lrcImported() {
        DispatchQueue.main.async {
            self.cache.removeAll()
            self.onlineMisses.removeAll()
            if self.trackID != nil { self.reloadCurrent() }
        }
    }

    func reloadCurrent() {
        if let id = trackID { cache[id] = nil; onlineMisses.remove(id) }
        load(for: AudioPlayer.shared.currentTrack, force: true)
    }

    /// Imports a .lrc/.txt file for the given track.
    func importLRC(from url: URL, for track: Track) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              LRCParser.parse(text, source: "") != nil else { return false }
        do {
            try text.write(to: LyricsStore.userLRCURL(for: track), atomically: true, encoding: .utf8)
        } catch { return false }
        cache[track.id] = nil
        load(for: track, force: true)
        return true
    }

    private func finish(_ l: Lyrics?, track: Track, gen: Int) {
        DispatchQueue.main.async {
            guard gen == self.generation else { return }
            if let l = l { self.cache[track.id] = l }
            self.lyrics = l
            self.isLoading = false
        }
    }

    // MARK: Sources

    private static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    static func loadLocal(_ track: Track) -> Lyrics? {
        let fm = FileManager.default
        // 1. .lrc imported for this song in the app
        if let t = readText(userLRCURL(for: track)), let l = LRCParser.parse(t, source: L("Archivo .lrc")) { return l }
        // 2. Sidecar .lrc next to the audio file in Documents
        let audioURL = Library.url(for: track)
        let sidecar = audioURL.deletingPathExtension().appendingPathExtension("lrc")
        if fm.fileExists(atPath: sidecar.path), let t = readText(sidecar),
           let l = LRCParser.parse(t, source: L("Archivo .lrc")) { return l }
        // 3. Cached online result
        if let t = readText(onlineURL(for: track)), let l = LRCParser.parse(t, source: "LRCLIB"), l.synced { return l }
        // 4. Embedded tags
        let embedded = embeddedLyrics(audioURL)
        if let e = embedded { return e }
        if let t = readText(onlineURL(for: track)), let l = LRCParser.parse(t, source: "LRCLIB") { return l }
        return nil
    }

    static func embeddedLyrics(_ url: URL) -> Lyrics? {
        let source = L("Etiquetas del archivo")
        var plainCandidate: Lyrics? = nil

        if url.pathExtension.lowercased() == "flac", let flac = FLACMetadata.read(url: url) {
            for key in ["SYNCEDLYRICS", "LYRICS", "UNSYNCEDLYRICS", "UNSYNCED LYRICS", "LYRICS-ENG"] {
                if let t = flac.tags[key], let l = LRCParser.parse(t, source: source) {
                    if l.synced { return l }
                    if plainCandidate == nil { plainCandidate = l }
                }
            }
        }

        let asset = AVURLAsset(url: url)
        let all = asset.metadata
        for item in AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .id3MetadataSynchronizedLyric) {
            if let d = item.dataValue, let l = SYLTParser.parse(d) { return l }
            if let s = item.stringValue, let l = LRCParser.parse(s, source: source), l.synced { return l }
        }
        var texts: [String] = []
        for id in [AVMetadataIdentifier.id3MetadataUnsynchronizedLyric, .iTunesMetadataLyrics] {
            for item in AVMetadataItem.metadataItems(from: all, filteredByIdentifier: id) {
                if let s = item.stringValue { texts.append(s) }
            }
        }
        if let s = asset.lyrics { texts.append(s) }
        for t in texts {
            if let l = LRCParser.parse(t, source: source) {
                if l.synced { return l }
                if plainCandidate == nil { plainCandidate = l }
            }
        }
        return plainCandidate
    }

    static func fetchOnline(_ track: Track, completion: @escaping (Lyrics?) -> Void) {
        let unknown = L("Artista desconocido")
        let artist = track.artist == unknown ? "" : track.artist
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [URLQueryItem(name: "track_name", value: track.title),
                     URLQueryItem(name: "artist_name", value: artist)]
        if !track.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: track.album)) }
        if track.duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))) }
        comps.queryItems = items

        func request(_ url: URL, _ done: @escaping (Any?) -> Void) {
            var req = URLRequest(url: url, timeoutInterval: 12)
            req.setValue("Slowed/1.0 (https://github.com/Harvlo/mornye-slowed-reverb)", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                guard let data = data, let http = resp as? HTTPURLResponse, http.statusCode == 200 else { done(nil); return }
                done(try? JSONSerialization.jsonObject(with: data))
            }.resume()
        }

        func lyricsFrom(_ obj: [String: Any]) -> (Lyrics, String)? {
            if let s = obj["syncedLyrics"] as? String, !s.isEmpty, let l = LRCParser.parse(s, source: "LRCLIB"), l.synced { return (l, s) }
            if let p = obj["plainLyrics"] as? String, !p.isEmpty, let l = LRCParser.parse(p, source: "LRCLIB") { return (l, p) }
            return nil
        }

        func save(_ raw: String) {
            try? raw.write(to: onlineURL(for: track), atomically: true, encoding: .utf8)
        }

        func search() {
            var s = URLComponents(string: "https://lrclib.net/api/search")!
            s.queryItems = [URLQueryItem(name: "q", value: (artist.isEmpty ? "" : artist + " ") + track.title)]
            guard let url = s.url else { completion(nil); return }
            request(url) { obj in
                guard let arr = obj as? [[String: Any]] else { completion(nil); return }
                // Prefer synced results with a close duration.
                let scored = arr.compactMap { item -> (Int, [String: Any])? in
                    var score = 0
                    if let s = item["syncedLyrics"] as? String, !s.isEmpty { score += 10 }
                    if let d = item["duration"] as? Double, track.duration > 0 {
                        let diff = abs(d - track.duration)
                        if diff < 3 { score += 5 } else if diff > 15 { score -= 10 }
                    }
                    return (score, item)
                }.sorted { $0.0 > $1.0 }
                for (score, item) in scored where score > -5 {
                    if let r = lyricsFrom(item) { save(r.1); completion(r.0); return }
                }
                completion(nil)
            }
        }

        guard !artist.isEmpty, let getURL = comps.url else {
            search()
            return
        }
        request(getURL) { obj in
            if let dict = obj as? [String: Any], let r = lyricsFrom(dict) {
                save(r.1); completion(r.0)
            } else {
                search()
            }
        }
    }
}
