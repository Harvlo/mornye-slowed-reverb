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

    static func artworkImage(for track: Track) -> UIImage? {
        guard track.hasArtwork else { return nil }
        return UIImage(contentsOfFile: artworkURL(for: track).path)
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

        let known = Set(tracks.map { $0.fileName })
        for name in audioFiles.sorted() where !known.contains(name) {
            tracks.append(makeTrack(fileName: name))
            changed = true
        }
        if changed { save() }
    }

    private func makeTrack(fileName: String) -> Track {
        let url = Library.documents.appendingPathComponent(fileName)
        let base = (fileName as NSString).deletingPathExtension
        var title = base
        var artist = "Artista desconocido"
        var duration: Double = 0
        var artworkData: Data? = nil

        let asset = AVURLAsset(url: url)
        let meta = asset.commonMetadata
        if let t = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .commonIdentifierTitle).first?.stringValue,
           !t.trimmingCharacters(in: .whitespaces).isEmpty {
            title = t
        }
        if let a = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .commonIdentifierArtist).first?.stringValue,
           !a.trimmingCharacters(in: .whitespaces).isEmpty {
            artist = a
        }
        artworkData = AVMetadataItem.metadataItems(from: meta, filteredByIdentifier: .commonIdentifierArtwork).first?.dataValue

        if let f = try? AVAudioFile(forReading: url), f.processingFormat.sampleRate > 0 {
            duration = Double(f.length) / f.processingFormat.sampleRate
        } else {
            let secs = CMTimeGetSeconds(asset.duration)
            if secs.isFinite { duration = secs }
        }

        var track = Track(fileName: fileName, title: title, artist: artist, duration: duration)
        if let data = artworkData, UIImage(data: data) != nil {
            if (try? data.write(to: Library.artworkURL(for: track), options: .atomic)) != nil {
                track.hasArtwork = true
            }
        }
        return track
    }

    // MARK: Import / delete

    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        var count = 0
        let fm = FileManager.default
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Library.audioExtensions.contains(ext) else { continue }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            // Already inside our Documents folder (opened in place)?
            if url.deletingLastPathComponent().standardizedFileURL.path == Library.documents.standardizedFileURL.path {
                count += 1
                continue
            }
            let dest = uniqueDestination(for: url.lastPathComponent)
            do {
                try fm.copyItem(at: url, to: dest)
                count += 1
            } catch {
                // Fallback: read through a file coordinator (iCloud / providers)
                var coordError: NSError?
                var ok = false
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
                    ok = (try? fm.copyItem(at: readURL, to: dest)) != nil
                }
                if ok { count += 1 }
            }
        }
        refresh()
        if count > 0 {
            lastMessage = count == 1 ? "1 canción añadida" : "\(count) canciones añadidas"
        } else if !urls.isEmpty {
            lastMessage = "No se pudo importar el archivo"
        }
        return count
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
