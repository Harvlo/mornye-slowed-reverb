import Foundation
import AVFoundation
import UIKit
import SwiftUI

enum AudioFormatInfo {
    /// e.g. "FLAC · 24-bit · 96 kHz", "MP3 · 44.1 kHz"
    static func describe(_ file: AVAudioFile, url: URL) -> String {
        let asbd = file.fileFormat.streamDescription.pointee
        let ext = url.pathExtension.lowercased()
        var codec: String
        var bits: UInt32 = asbd.mBitsPerChannel
        switch asbd.mFormatID {
        case kAudioFormatFLAC:
            codec = "FLAC"
            bits = losslessBits(asbd.mFormatFlags) ?? bits
        case kAudioFormatAppleLossless:
            codec = "ALAC"
            bits = losslessBits(asbd.mFormatFlags) ?? bits
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2:
            codec = "AAC"; bits = 0
        case kAudioFormatMPEGLayer3:
            codec = "MP3"; bits = 0
        case kAudioFormatOpus:
            codec = "Opus"; bits = 0
        case kAudioFormatLinearPCM:
            switch ext {
            case "aif", "aiff": codec = "AIFF"
            case "caf": codec = "CAF"
            default: codec = "WAV"
            }
        default:
            codec = ext.uppercased()
        }
        if codec.isEmpty { codec = "Audio" }
        var parts = [codec]
        if bits > 0 { parts.append("\(bits)-bit") }
        let khz = asbd.mSampleRate / 1000.0
        if khz > 0 {
            let s = khz.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            parts.append("\(s) kHz")
        }
        return parts.joined(separator: " · ")
    }

    private static func losslessBits(_ flags: AudioFormatFlags) -> UInt32? {
        switch flags {
        case kAppleLosslessFormatFlag_16BitSourceData: return 16
        case kAppleLosslessFormatFlag_20BitSourceData: return 20
        case kAppleLosslessFormatFlag_24BitSourceData: return 24
        case kAppleLosslessFormatFlag_32BitSourceData: return 32
        default: return nil
        }
    }
}

enum ArtworkColor {
    private static var cache: [UUID: UIColor] = [:]

    /// Average color of the artwork, biased toward saturated pixels, darkened for a player background.
    static func background(for track: Track?) -> UIColor {
        let fallback = UIColor(red: 0.20, green: 0.12, blue: 0.36, alpha: 1)
        guard let track = track else { return fallback }
        if let c = cache[track.id] { return c }
        guard let img = Library.artworkImage(for: track), let cg = img.cgImage else { return fallback }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return fallback }
        var r = 0.0, g = 0.0, b = 0.0, wsum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pr = Double(pixels[i]) / 255, pg = Double(pixels[i + 1]) / 255, pb = Double(pixels[i + 2]) / 255
            let mx = max(pr, pg, pb), mn = min(pr, pg, pb)
            let sat = mx == 0 ? 0 : (mx - mn) / mx
            let w = 0.15 + sat * sat + (mx > 0.15 ? 0.2 : 0)
            r += pr * w; g += pg * w; b += pb * w; wsum += w
        }
        guard wsum > 0 else { return fallback }
        let base = UIColor(red: r / wsum, green: g / wsum, blue: b / wsum, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        let color = UIColor(hue: h, saturation: min(s * 1.1, 0.85), brightness: min(max(br * 0.6, 0.18), 0.42), alpha: 1)
        cache[track.id] = color
        return color
    }

    private static var accentCache: [UUID: UIColor] = [:]

    /// Vivid accent taken from the artwork (e.g. pink for a pink cover); app accent when there is no art.
    static func accent(for track: Track?) -> UIColor {
        let fallback = UIColor(Theme.accent)
        guard let track = track else { return fallback }
        if let c = accentCache[track.id] { return c }
        guard let img = Library.artworkImage(for: track), let cg = img.cgImage else { return fallback }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return fallback }
        // Hue histogram weighted by saturation * brightness.
        var bins = [Double](repeating: 0, count: 24)
        var sums = [(Double, Double)](repeating: (0, 0), count: 24)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let c = UIColor(red: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255,
                            blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            guard s > 0.2, b > 0.25 else { continue }
            let w = Double(s * s * b)
            let bin = min(Int(h * 24), 23)
            bins[bin] += w
            sums[bin].0 += Double(s) * w
            sums[bin].1 += Double(b) * w
        }
        guard let best = bins.indices.max(by: { bins[$0] < bins[$1] }), bins[best] > 0.4 else {
            accentCache[track.id] = fallback
            return fallback
        }
        let hue = (Double(best) + 0.5) / 24.0
        let sat = sums[best].0 / bins[best]
        let color = UIColor(hue: CGFloat(hue), saturation: CGFloat(min(max(sat, 0.5), 0.75)), brightness: 0.95, alpha: 1)
        accentCache[track.id] = color
        return color
    }

    static func invalidate(_ id: UUID) { cache[id] = nil; accentCache[id] = nil }
}
