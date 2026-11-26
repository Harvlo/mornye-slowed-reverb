import Foundation

/// Minimal FLAC metadata reader: Vorbis comments (TITLE, ARTIST, ALBUM, ...) and PICTURE blocks.
struct FLACMetadata {
    var tags: [String: String] = [:]
    var picture: Data? = nil

    static func read(url: URL) -> FLACMetadata? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4), magic == Data("fLaC".utf8) else { return nil }

        var result = FLACMetadata()
        var bestPictureType: UInt32 = 999
        var isLast = false
        var guardCount = 0
        while !isLast && guardCount < 128 {
            guardCount += 1
            guard let header = try? handle.read(upToCount: 4), header.count == 4 else { break }
            let h = [UInt8](header)
            isLast = (h[0] & 0x80) != 0
            let type = h[0] & 0x7F
            let length = Int(h[1]) << 16 | Int(h[2]) << 8 | Int(h[3])
            if type == 4 || type == 6 {
                guard length < 64 * 1024 * 1024, let body = try? handle.read(upToCount: length), body.count == length else { break }
                if type == 4 {
                    parseVorbis([UInt8](body), into: &result.tags)
                } else if let (picType, data) = parsePicture([UInt8](body)) {
                    // Prefer front cover (3), otherwise the first picture.
                    let rank: UInt32 = picType == 3 ? 0 : (picType + 1)
                    if result.picture == nil || rank < bestPictureType {
                        result.picture = data
                        bestPictureType = rank
                    }
                }
            } else {
                let offset = (try? handle.offset()) ?? 0
                do { try handle.seek(toOffset: offset + UInt64(length)) } catch { break }
            }
        }
        return result
    }

    private static func le32(_ b: [UInt8], _ i: Int) -> Int? {
        guard i + 4 <= b.count else { return nil }
        return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
    }

    private static func be32(_ b: [UInt8], _ i: Int) -> Int? {
        guard i + 4 <= b.count else { return nil }
        return Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }

    private static func parseVorbis(_ b: [UInt8], into tags: inout [String: String]) {
        var i = 0
        guard let vendorLen = le32(b, i) else { return }
        i += 4 + vendorLen
        guard let count = le32(b, i) else { return }
        i += 4
        for _ in 0..<min(count, 10000) {
            guard let len = le32(b, i) else { return }
            i += 4
            guard len >= 0, i + len <= b.count else { return }
            if let s = String(bytes: b[i..<(i + len)], encoding: .utf8), let eq = s.firstIndex(of: "=") {
                let key = s[..<eq].uppercased()
                let value = String(s[s.index(after: eq)...])
                if tags[key] == nil { tags[key] = value }
            }
            i += len
        }
    }

    private static func parsePicture(_ b: [UInt8]) -> (UInt32, Data)? {
        var i = 0
        guard let picType = be32(b, i) else { return nil }
        i += 4
        guard let mimeLen = be32(b, i) else { return nil }
        i += 4 + mimeLen
        guard let descLen = be32(b, i) else { return nil }
        i += 4 + descLen
        i += 16 // width, height, depth, colors
        guard let dataLen = be32(b, i) else { return nil }
        i += 4
        guard dataLen > 0, i + dataLen <= b.count else { return nil }
        return (UInt32(picType), Data(b[i..<(i + dataLen)]))
    }
}
