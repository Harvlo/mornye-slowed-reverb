import Foundation
import AVFoundation

enum ExportError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .failed(let msg): return msg
        }
    }
}

enum Exporter {
    /// Renders the track offline with the given effects and writes it into Documents.
    /// Returns the URL of the new file. Runs synchronously; call from a background queue.
    static func export(track: Track, settings: EffectSettings, progress: @escaping (Double) -> Void) throws -> URL {
        let source = try AVAudioFile(forReading: Library.url(for: track))
        let format = source.processingFormat

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        let timePitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 11)
        let lowPass = AVAudioUnitEQ(numberOfBands: 1)
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()

        for node in [player, varispeed, timePitch, eq, lowPass, delay, reverb] as [AVAudioNode] {
            engine.attach(node)
        }
        engine.connect(player, to: varispeed, format: format)
        engine.connect(varispeed, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: lowPass, format: format)
        engine.connect(lowPass, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        reverb.loadFactoryPreset(ReverbRoom.all[EffectChain.roomIndex(settings)].preset)
        EffectChain.apply(settings, varispeed: varispeed, timePitch: timePitch, eq: eq,
                          lowPass: lowPass, delay: delay, reverb: reverb)

        let maxFrames: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
        try engine.start()
        player.scheduleFile(source, at: nil, completionHandler: nil)
        player.play()

        let speed = Double(max(settings.effectiveSpeed, 0.1))
        let tailSeconds: Double = (settings.slowedOn && settings.reverbMix > 0) || settings.echoOn ? 3.0 : 0.3
        let total = AVAudioFramePosition(Double(source.length) / speed + tailSeconds * format.sampleRate)

        var suffix = settings.slowedOn ? (settings.effectiveSpeed > 1 ? " (nightcore)" : " (slowed + reverb)") : " (efectos)"
        if settings.slowedOn && settings.effectiveSpeed == 1 { suffix = " (reverb)" }
        let safeTitle = track.title.replacingOccurrences(of: "/", with: "-")
        let useAAC = format.sampleRate <= 48000
        let ext = useAAC ? "m4a" : "wav"
        let outURL = Library.shared.uniqueDestination(for: safeTitle + suffix + "." + ext)

        var fileSettings: [String: Any] = [
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount
        ]
        if useAAC {
            fileSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            fileSettings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        } else {
            fileSettings[AVFormatIDKey] = kAudioFormatLinearPCM
            fileSettings[AVLinearPCMBitDepthKey] = 16
            fileSettings[AVLinearPCMIsFloatKey] = false
            fileSettings[AVLinearPCMIsBigEndianKey] = false
        }

        do {
            let out = try AVAudioFile(forWriting: outURL, settings: fileSettings,
                                      commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                                frameCapacity: engine.manualRenderingMaximumFrameCount) else {
                throw ExportError.failed("No se pudo crear el búfer de audio")
            }
            var stalls = 0
            var lastReported = -1
            while engine.manualRenderingSampleTime < total {
                let remaining = total - engine.manualRenderingSampleTime
                let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), remaining))
                let status = try engine.renderOffline(frames, to: buffer)
                switch status {
                case .success:
                    try out.write(from: buffer)
                    stalls = 0
                case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                    stalls += 1
                    if stalls > 1000 { throw ExportError.failed("El render se detuvo") }
                case .error:
                    throw ExportError.failed("Error al procesar el audio")
                @unknown default:
                    throw ExportError.failed("Error desconocido al procesar")
                }
                let pct = Int(Double(engine.manualRenderingSampleTime) / Double(total) * 100)
                if pct != lastReported {
                    lastReported = pct
                    progress(Double(pct) / 100.0)
                }
            }
        } catch {
            player.stop()
            engine.stop()
            try? FileManager.default.removeItem(at: outURL)
            throw error
        }
        player.stop()
        engine.stop()
        return outURL
    }
}
