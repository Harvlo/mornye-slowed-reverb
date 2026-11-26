import Foundation
import AVFoundation
import UIKit
import Combine

final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var tracks: [Track] = []
    @Published var lastMessage: String? = nil

    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "aac", "aif", "aiff", "caf", "mp4"]

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Slowed", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var artworkDir: URL {
        let url = support.appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var indexURL: URL { Library.support.appendingPathComponent("library.json") }

    static func url(for track: Track) -> URL {
        documents.appendingPathComponent(track.fileName)
    }

    static func artworkURL(for track: Track) -> URL {
        artworkDir.appendingPathComponent(track.id.uuidString + ".img")
    }

    private static let artworkCache = NSCache<NSString, UIImage>()

    static func artworkImage(for track: Track) -> UIImage? {
        guard track.hasArtwork else { return nil }
        let key = track.id.uuidString as NSString
        if let cached = artworkCache.object(forKey: key) { return cached }
        guard let img = UIImage(contentsOfFile: artworkURL(for: track).path) else { return nil }
        artworkCache.setObject(img, forKey: key)
        return img
    }

    /// Downscales big covers (often 3000px) so lists and the lock screen stay fast.
    static func saveArtwork(_ data: Data, for track: Track) -> Bool {
        guard let img = UIImage(data: data) else { return false }
        let maxSide: CGFloat = 1000
        let size = img.size
        var output = data
        if max(size.width, size.height) > maxSide || data.count > 600_000 {
            let scale = min(1, maxSide / max(size.width, size.height))
            let newSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                img.draw(in: CGRect(origin: .zero, size: newSize))
            }
            if let jpg = resized.jpegData(compressionQuality: 0.85) { output = jpg }
        }
        artworkCache.removeObject(forKey: track.id.uuidString as NSString)
        return (try? output.write(to: artworkURL(for: track), options: .atomic)) != nil
    }

    init() {
        load()
        refresh()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Track].self, from: data) else { return }
        tracks = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tracks) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: Scanning

    /// Syncs the library with the files in Documents (files can be added from the Files app).
    func refresh() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: Library.documents.path)) ?? []
        let audioFiles = files.filter { Library.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        let fileSet = Set(audioFiles)
        var changed = false

        let before = tracks.count
        tracks.removeAll { !fileSet.contains($0.fileName) }
        if tracks.count != before { changed = true }

        // Re-read tags for tracks imported by older versions (FLAC covers, album, explicit).
        for i in tracks.indices where tracks[i].metaVersion < Track.currentMetaVersion {
            let old = tracks[i]
            var fresh = makeTrack(fileName: old.fileName, reuseID: old.id)
            fresh.addedAt = old.addedAt
            tracks[i] = fresh
            changed = true
        }

        let known = Set(tracks.map { $0.fileName })
        for name in audioFiles.sorted() where !known.contains(name) {
            tracks.append(makeTrack(fileName: name, reuseID: nil))
            changed = true
        }
        if changed { save() }
    }

    private func makeTrack(fileName: String, reuseID: UUID?) -> Track {
        let url = Library.documents.appendingPathComponent(fileName)
        let base = (fileName as NSString).deletingPathExtension
        var title = ""
        var artist = ""
        var album = ""
        var explicit = false
        var duration: Double = 0
        var artworkData: Data? = nil

        let asset = AVURLAsset(url: url)
        let common = asset.commonMetadata
        func commonString(_ id: AVMetadataIdentifier) -> String {
            let v = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: id).first?.stringValue ?? ""
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        title = commonString(.commonIdentifierTitle)
        artist = commonString(.commonIdentifierArtist)
        album = commonString(.commonIdentifierAlbumName)
        artworkData = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork).first?.dataValue

        // Format-specific metadata (ID3 APIC, iTunes covr / rtng, ITUNESADVISORY).
        let all = asset.metadata
        if artworkData == nil {
            let ids: [AVMetadataIdentifier] = [.id3MetadataAttachedPicture, .iTunesMetadataCoverArt]
            for id in ids {
                if let d = AVMetadataItem.metadataItems(from: all, filteredByIdentifier: id).first?.dataValue {
                    artworkData = d
                    break
                }
            }
        }
        if artist.isEmpty {
            artist = AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .iTunesMetadataAlbumArtist).first?.stringValue ?? ""
        }
        if let rating = AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .iTunesMetadataContentRating).first?.numberValue?.intValue {
            explicit = (rating == 1 || rating == 4)
        }
        for item in all where !explicit {
            let desc = String(describing: item.identifier?.rawValue ?? "") + " " + String(describing: item.extraAttributes ?? [:])
            if desc.uppercased().contains("ADVISORY"), let v = item.stringValue, v == "1" || v == "4" {
                explicit = true
            }
        }

        // FLAC: Vorbis comments + PICTURE blocks (AVFoundation often exposes neither).
        if url.pathExtension.lowercased() == "flac", let flac = FLACMetadata.read(url: url) {
            let t = flac.tags
            if title.isEmpty { title = t["TITLE"] ?? "" }
            if artist.isEmpty { artist = t["ARTIST"] ?? t["ALBUMARTIST"] ?? t["ALBUM ARTIST"] ?? "" }
            if album.isEmpty { album = t["ALBUM"] ?? "" }
            if !explicit {
                let adv = (t["ITUNESADVISORY"] ?? t["EXPLICIT"] ?? t["CONTENTRATING"] ?? "").lowercased()
                explicit = adv == "1" || adv == "4" || adv == "explicit" || adv == "true" || adv == "yes"
            }
            if artworkData == nil { artworkData = flac.picture }
        }

        if title.isEmpty { title = base }
        if artist.isEmpty { artist = L("Artista desconocido") }

        if let f = try? AVAudioFile(forReading: url), f.processingFormat.sampleRate > 0 {
            duration = Double(f.length) / f.processingFormat.sampleRate
        } else {
            let secs = CMTimeGetSeconds(asset.duration)
            if secs.isFinite { duration = secs }
        }

        var track = Track(fileName: fileName, title: title, artist: artist, album: album,
                          explicit: explicit, duration: duration)
        if let id = reuseID { track.id = id }
        if let data = artworkData, Library.saveArtwork(data, for: track) {
            track.hasArtwork = true
        } else {
            try? FileManager.default.removeItem(at: Library.artworkURL(for: track))
        }
        return track
    }

    // MARK: Import / delete

    @Published private(set) var isImporting: Bool = false
    @Published private(set) var importStatus: String = ""
    @Published var importAlert: String? = nil

    /// Imports files off the main thread. Handles security-scoped URLs, iCloud files
    /// (via NSFileCoordinator, which downloads them first) and picker copies (moved instead of copied).
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        importStatus = urls.count == 1 ? L("Importando…") : L("Importando %lld de %lld…", 0, urls.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var imported = 0
            var failures: [String] = []
            for (i, url) in urls.enumerated() {
                let name = url.lastPathComponent
                do {
                    try self.importOne(url)
                    imported += 1
                } catch {
                    failures.append("• \(name): \(error.localizedDescription)")
                }
                let done = i + 1
                DispatchQueue.main.async {
                    if urls.count > 1 { self.importStatus = L("Importando %lld de %lld…", done, urls.count) }
                }
            }
            DispatchQueue.main.async {
                self.isImporting = false
                self.refresh()
                if imported > 0 {
                    self.lastMessage = imported == 1 ? L("1 canción añadida") : L("%lld canciones añadidas", imported)
                }
                if !failures.isEmpty {
                    self.importAlert = L("No se pudieron importar %lld archivo(s):", failures.count) + "\n" + failures.prefix(6).joined(separator: "\n")
                }
            }
        }
    }

    private func importOne(_ url: URL) throws {
        let fm = FileManager.default
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        // Already inside our Documents folder (opened in place)? Nothing to copy.
        if url.deletingLastPathComponent().standardizedFileURL.path == Library.documents.standardizedFileURL.path {
            return
        }

        var ext = url.pathExtension.lowercased()
        if ext.isEmpty { ext = "m4a" }
        var fileName = url.lastPathComponent
        if url.pathExtension.isEmpty { fileName += "." + ext }
        let dest = uniqueDestination(for: fileName)

        // Files handed over by the picker (asCopy) or "Open in" live in our tmp/Inbox: move them.
        let path = url.standardizedFileURL.path
        let ownTemp = path.hasPrefix(fm.temporaryDirectory.standardizedFileURL.path) || path.contains("/Inbox/")

        var coordError: NSError?
        var innerError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { readURL in
            do {
                if ownTemp {
                    do { try fm.moveItem(at: readURL, to: dest) } catch { try fm.copyItem(at: readURL, to: dest) }
                } else {
                    try fm.copyItem(at: readURL, to: dest)
                }
            } catch {
                innerError = error
            }
        }
        if let e = coordError ?? (innerError as NSError?) { throw e }

        // Make sure we can actually play it; otherwise remove it and report.
        if !Library.audioExtensions.contains(dest.pathExtension.lowercased()) || (try? AVAudioFile(forReading: dest)) == nil {
            try? fm.removeItem(at: dest)
            throw NSError(domain: "Slowed", code: 1, userInfo: [NSLocalizedDescriptionKey: L("formato no compatible")])
        }
    }

    func uniqueDestination(for fileName: String) -> URL {
        let fm = FileManager.default
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = Library.documents.appendingPathComponent(fileName)
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = Library.documents.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    func delete(_ track: Track) {
        try? FileManager.default.removeItem(at: Library.url(for: track))
        try? FileManager.default.removeItem(at: Library.artworkURL(for: track))
        tracks.removeAll { $0.id == track.id }
        save()
    }

    func rename(_ track: Track, title: String, artist: String) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[i].title = title
        tracks[i].artist = artist
        save()
    }
}
