import Foundation
import AVFoundation
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.64, green: 0.42, blue: 1.0)
    static let accent2 = Color(red: 0.98, green: 0.36, blue: 0.68)
    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct Track: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var fileName: String
    var title: String
    var artist: String
    var duration: Double
    var hasArtwork: Bool = false
    var addedAt: Date = Date()
}

enum RepeatMode: Int, Codable {
    case off = 0
    case all = 1
    case one = 2
}

struct ReverbRoom {
    let name: String
    let preset: AVAudioUnitReverbPreset

    static let all: [ReverbRoom] = [
        ReverbRoom(name: "Habitación pequeña", preset: .smallRoom),
        ReverbRoom(name: "Habitación", preset: .mediumRoom),
        ReverbRoom(name: "Habitación grande", preset: .largeRoom),
        ReverbRoom(name: "Auditorio", preset: .mediumHall),
        ReverbRoom(name: "Auditorio grande", preset: .largeHall),
        ReverbRoom(name: "Cámara", preset: .largeChamber),
        ReverbRoom(name: "Placa", preset: .plate),
        ReverbRoom(name: "Catedral", preset: .cathedral)
    ]
}

struct EQPreset {
    let name: String
    let gains: [Float]

    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let labels: [String] = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

    static let all: [EQPreset] = [
        EQPreset(name: "Plano", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bass Boost", gains: [7, 6, 4, 2, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Voces", gains: [-2, -2, -1, 1, 3, 4, 4, 2, 0, -1]),
        EQPreset(name: "Pop", gains: [-1, 1, 3, 4, 3, 0, -1, -1, 0, 1]),
        EQPreset(name: "Rock", gains: [4, 3, 2, 0, -1, -1, 1, 2, 3, 4]),
        EQPreset(name: "Hip-Hop", gains: [5, 4, 2, 3, -1, -1, 1, 0, 2, 3]),
        EQPreset(name: "Electrónica", gains: [5, 4, 1, 0, -2, 1, 0, 1, 4, 5]),
        EQPreset(name: "Acústica", gains: [3, 3, 2, 1, 1, 1, 2, 3, 2, 1]),
        EQPreset(name: "Agudos", gains: [0, 0, 0, 0, 0, 1, 3, 5, 6, 7]),
        EQPreset(name: "Nocturno", gains: [2, 1, 0, 0, -1, -2, -3, -3, -4, -5])
    ]
}

struct EffectSettings: Codable, Equatable {
    // Slowed + Reverb
    var slowedOn: Bool = false
    var speed: Float = 0.8
    var keepPitch: Bool = false
    var pitchSemitones: Float = 0
    var reverbMix: Float = 45
    var reverbRoom: Int = 4

    // Ecualizador
    var eqOn: Bool = false
    var eqGains: [Float] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var eqPresetName: String = "Plano"
    var bassBoost: Float = 0

    // Efectos extra
    var eightDOn: Bool = false
    var eightDCycle: Float = 8
    var echoOn: Bool = false
    var echoTime: Float = 0.35
    var echoFeedback: Float = 35
    var echoMix: Float = 25
    var underwaterOn: Bool = false
    var underwaterCutoff: Float = 700

    var effectiveSpeed: Float { slowedOn ? speed : 1.0 }

    mutating func applySpeedPreset(_ name: String) {
        slowedOn = true
        keepPitch = false
        pitchSemitones = 0
        switch name {
        case "Super slowed":
            speed = 0.7; reverbMix = 60; reverbRoom = 7
        case "Nightcore":
            speed = 1.25; reverbMix = 10; reverbRoom = 1
        case "Daycore":
            speed = 0.85; reverbMix = 25; reverbRoom = 2
        case "Solo reverb":
            speed = 1.0; reverbMix = 50; reverbRoom = 4
        default: // Slowed
            speed = 0.8; reverbMix = 45; reverbRoom = 4
        }
    }

    static let speedPresets = ["Slowed", "Super slowed", "Daycore", "Nightcore", "Solo reverb"]
}

enum EffectChain {
    static func roomIndex(_ s: EffectSettings) -> Int {
        return min(max(s.reverbRoom, 0), ReverbRoom.all.count - 1)
    }

    /// Applies settings to a set of nodes. Used by the live player and the exporter.
    static func apply(_ s: EffectSettings,
                      varispeed: AVAudioUnitVarispeed,
                      timePitch: AVAudioUnitTimePitch,
                      eq: AVAudioUnitEQ,
                      lowPass: AVAudioUnitEQ,
                      delay: AVAudioUnitDelay,
                      reverb: AVAudioUnitReverb) {
        let speed = s.effectiveSpeed
        if s.slowedOn && s.keepPitch {
            varispeed.rate = 1.0
            timePitch.rate = speed
        } else {
            varispeed.rate = speed
            timePitch.rate = 1.0
        }
        timePitch.pitch = s.slowedOn ? s.pitchSemitones * 100.0 : 0
        timePitch.bypass = (timePitch.rate == 1.0 && timePitch.pitch == 0)
        varispeed.bypass = (varispeed.rate == 1.0)

        reverb.wetDryMix = s.slowedOn ? s.reverbMix : 0
        reverb.bypass = !(s.slowedOn && s.reverbMix > 0)

        var maxGain: Float = 0
        for i in 0..<10 {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = EQPreset.frequencies[i]
            band.bandwidth = 1.0
            let g: Float = s.eqOn && i < s.eqGains.count ? s.eqGains[i] : 0
            band.gain = g
            band.bypass = false
            maxGain = max(maxGain, g)
        }
        let bass = eq.bands[10]
        bass.filterType = .lowShelf
        bass.frequency = 90
        bass.bandwidth = 1.0
        bass.gain = s.bassBoost
        bass.bypass = s.bassBoost <= 0
        maxGain = max(maxGain, s.bassBoost)
        eq.globalGain = -min(maxGain, 12) * 0.5
        eq.bypass = !(s.eqOn || s.bassBoost > 0)

        let lp = lowPass.bands[0]
        lp.filterType = .lowPass
        lp.frequency = s.underwaterCutoff
        lp.bandwidth = 0.5
        lp.bypass = false
        lowPass.globalGain = s.underwaterOn ? 3 : 0
        lowPass.bypass = !s.underwaterOn

        delay.delayTime = TimeInterval(s.echoTime)
        delay.feedback = s.echoFeedback
        delay.wetDryMix = s.echoMix
        delay.lowPassCutoff = 12000
        delay.bypass = !s.echoOn
    }
}

func formatTime(_ t: Double) -> String {
    guard t.isFinite, t >= 0 else { return "0:00" }
    let total = Int(t.rounded(.down))
    return String(format: "%d:%02d", total / 60, total % 60)
}
