import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine
import SwiftUI

final class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()

    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int? = nil
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var shuffle: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var errorMessage: String? = nil
    @Published private(set) var formatInfo: String = ""
    @Published var settings: EffectSettings {
        didSet {
            if settings != oldValue {
                applySettings()
                saveSettings()
                if settings.effectiveSpeed != oldValue.effectiveSpeed { updateNowPlaying() }
            }
        }
    }

    var currentTrack: Track? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private let timePitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 11)
    private let lowPass = AVAudioUnitEQ(numberOfBands: 1)
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()
    private let panMixer = AVAudioMixerNode()

    private var file: AVAudioFile?
    private var connectedFormat: AVAudioFormat?
    private var startFrame: AVAudioFramePosition = 0
    private var generation: Int = 0
    private var originalQueue: [Track] = []
    private var tickTimer: Timer?
    private var panTimer: Timer?
    private var panPhase: Double = 0
    private var loadedRoom: Int = -1
    private var currentArtwork: MPMediaItemArtwork?
    private var observers: [NSObjectProtocol] = []

    private static let settingsKey = "effectSettings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: AudioPlayer.settingsKey),
           let s = try? JSONDecoder().decode(EffectSettings.self, from: data) {
            settings = s
        } else {
            settings = EffectSettings()
        }
        repeatMode = RepeatMode(rawValue: UserDefaults.standard.integer(forKey: "repeatMode")) ?? .off

        engine.attach(player)
        engine.attach(varispeed)
        engine.attach(timePitch)
        engine.attach(eq)
        engine.attach(lowPass)
        engine.attach(delay)
        engine.attach(reverb)
        engine.attach(panMixer)
        if let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) {
            connectGraph(format: fmt)
        }
        applySettings()

        configureSession()
        setupRemoteCommands()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification,
                                        object: AVAudioSession.sharedInstance(), queue: nil) { [weak self] n in
            self?.handleInterruption(n)
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification,
                                        object: AVAudioSession.sharedInstance(), queue: nil) { [weak self] n in
            self?.handleRouteChange(n)
        })
        observers.append(nc.addObserver(forName: NSNotification.Name.AVAudioEngineConfigurationChange,
                                        object: engine, queue: nil) { [weak self] n in
            self?.handleEngineConfigChange(n)
        })
    }

    // MARK: Graph

    private func connectGraph(format: AVAudioFormat) {
        engine.connect(player, to: varispeed, format: format)
        engine.connect(varispeed, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: lowPass, format: format)
        engine.connect(lowPass, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: panMixer, format: format)
        engine.connect(panMixer, to: engine.mainMixerNode, format: format)
        connectedFormat = format
    }

    private func ensureGraph(for format: AVAudioFormat) {
        if let c = connectedFormat, c.sampleRate == format.sampleRate, c.channelCount == format.channelCount,
           c.commonFormat == format.commonFormat, c.isInterleaved == format.isInterleaved {
            return
        }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        connectGraph(format: format)
        if wasRunning { try? engine.start() }
    }

    private func applySettings() {
        let room = EffectChain.roomIndex(settings)
        if room != loadedRoom {
            reverb.loadFactoryPreset(ReverbRoom.all[room].preset)
            loadedRoom = room
        }
        EffectChain.apply(settings, varispeed: varispeed, timePitch: timePitch, eq: eq,
                          lowPass: lowPass, delay: delay, reverb: reverb)
        updatePanTimer()
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: AudioPlayer.settingsKey)
        }
    }

    func resetEffects() {
        settings = EffectSettings()
    }

    // MARK: Session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
    }

    private func startEngineIfNeeded() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // continue anyway
        }
        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                errorMessage = L("No se pudo iniciar el audio: %@", error.localizedDescription)
                return false
            }
        }
        return true
    }

    // MARK: Queue control

    func play(tracks: [Track], startAt index: Int) {
        guard tracks.indices.contains(index) else { return }
        originalQueue = tracks
        if shuffle {
            var rest = tracks
            let first = rest.remove(at: index)
            rest.shuffle()
            queue = [first] + rest
            currentIndex = 0
        } else {
            queue = tracks
            currentIndex = index
        }
        loadCurrent(autoplay: true)
    }

    func playNext(_ track: Track) {
        if queue.isEmpty {
            play(tracks: [track], startAt: 0)
            return
        }
        let insertAt = (currentIndex ?? -1) + 1
        queue.insert(track, at: min(insertAt, queue.count))
        originalQueue.append(track)
    }

    func addToQueue(_ track: Track) {
        if queue.isEmpty {
            play(tracks: [track], startAt: 0)
            return
        }
        queue.append(track)
        originalQueue.append(track)
    }

    func removeFromQueue(at offsets: IndexSet) {
        guard let cur = currentIndex else { return }
        let removingCurrent = offsets.contains(cur)
        let removedBefore = offsets.filter { $0 < cur }.count
        let removedIDs = offsets.map { queue[$0].id }
        queue.remove(atOffsets: offsets)
        originalQueue.removeAll { removedIDs.contains($0.id) }
        if queue.isEmpty {
            stopAll()
            return
        }
        if removingCurrent {
            currentIndex = min(cur - removedBefore, queue.count - 1)
            loadCurrent(autoplay: isPlaying)
        } else {
            currentIndex = cur - removedBefore
        }
    }

    func moveInQueue(from source: IndexSet, to destination: Int) {
        guard let cur = currentIndex, queue.indices.contains(cur) else { return }
        let curID = queue[cur].id
        queue.move(fromOffsets: source, toOffset: destination)
        currentIndex = queue.firstIndex { $0.id == curID }
    }

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        loadCurrent(autoplay: true)
    }

    func trackRemovedFromLibrary(_ track: Track) {
        guard let i = queue.firstIndex(where: { $0.id == track.id }) else { return }
        removeFromQueue(at: IndexSet(integer: i))
    }

    func toggleShuffle() {
        shuffle.toggle()
        guard let cur = currentTrack else { return }
        if shuffle {
            originalQueue = queue
            var rest = queue.filter { $0.id != cur.id }
            rest.shuffle()
            queue = [cur] + rest
            currentIndex = 0
        } else {
            if originalQueue.isEmpty { originalQueue = queue }
            queue = originalQueue
            currentIndex = queue.firstIndex { $0.id == cur.id } ?? 0
        }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode")
    }

    // MARK: Loading

    private func loadCurrent(autoplay: Bool) {
        guard let track = currentTrack else { stopAll(); return }
        let url = Library.url(for: track)
        let f: AVAudioFile
        do {
            f = try AVAudioFile(forReading: url)
        } catch {
            errorMessage = L("No se pudo abrir «%@»", track.title)
            return
        }
        generation += 1
        player.stop()
        file = f
        ensureGraph(for: f.processingFormat)
        duration = Double(f.length) / f.processingFormat.sampleRate
        currentTime = 0
        formatInfo = AudioFormatInfo.describe(f, url: url)
        loadArtwork(for: track)
        LyricsStore.shared.load(for: track)
        schedule(from: 0)
        if autoplay {
            play()
        } else {
            updateNowPlaying()
        }
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let f = file else { return }
        let start = max(0, min(frame, f.length))
        startFrame = start
        let remaining = f.length - start
        guard remaining > 0 else { return }
        let gen = generation
        player.scheduleSegment(f, startingFrame: start, frameCount: AVAudioFrameCount(remaining), at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                self?.segmentFinished(generation: gen)
            }
        }
    }

    private func segmentFinished(generation gen: Int) {
        guard gen == generation else { return }
        if repeatMode == .one {
            seek(to: 0)
            if !isPlaying { play() }
            return
        }
        advance(auto: true)
    }

    // MARK: Transport

    func play() {
        guard file != nil else {
            if currentTrack != nil { loadCurrent(autoplay: true) }
            return
        }
        guard startEngineIfNeeded() else { return }
        player.play()
        isPlaying = true
        startTicking()
        updatePanTimer()
        updateNowPlaying()
    }

    func pause() {
        currentTime = computeCurrentTime()
        player.pause()
        isPlaying = false
        stopTicking()
        updatePanTimer()
        updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func next() { advance(auto: false) }

    private func advance(auto: Bool) {
        guard let i = currentIndex, !queue.isEmpty else { return }
        if i + 1 < queue.count {
            currentIndex = i + 1
            loadCurrent(autoplay: true)
        } else if repeatMode == .all || !auto {
            currentIndex = 0
            loadCurrent(autoplay: repeatMode == .all || (!auto && isPlaying))
        } else {
            // End of queue
            generation += 1
            player.stop()
            isPlaying = false
            stopTicking()
            updatePanTimer()
            currentTime = 0
            schedule(from: 0)
            updateNowPlaying()
        }
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard let i = currentIndex else { return }
        if i > 0 {
            currentIndex = i - 1
            loadCurrent(autoplay: true)
        } else if repeatMode == .all, !queue.isEmpty {
            currentIndex = queue.count - 1
            loadCurrent(autoplay: true)
        } else {
            seek(to: 0)
        }
    }

    func seek(to seconds: Double) {
        guard let f = file else { return }
        let sr = f.processingFormat.sampleRate
        let clamped = max(0, min(seconds, duration))
        let frame = AVAudioFramePosition(clamped * sr)
        let wasPlaying = isPlaying
        generation += 1
        player.stop()
        currentTime = clamped
        schedule(from: frame)
        if wasPlaying {
            if startEngineIfNeeded() { player.play() }
        }
        updateNowPlaying()
    }

    private func stopAll() {
        generation += 1
        player.stop()
        file = nil
        isPlaying = false
        currentIndex = nil
        queue = []
        originalQueue = []
        currentTime = 0
        duration = 0
        stopTicking()
        updatePanTimer()
        formatInfo = ""
        LyricsStore.shared.load(for: nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Precise position in song time (for lyrics). Accounts for the playback rate automatically,
    /// because it counts file frames rendered by the player node.
    func livePosition() -> Double {
        return isPlaying ? computeCurrentTime() : currentTime
    }

    private func computeCurrentTime() -> Double {
        guard let f = file else { return 0 }
        var frame = startFrame
        if let nodeTime = player.lastRenderTime, let pt = player.playerTime(forNodeTime: nodeTime) {
            frame += pt.sampleTime
        } else {
            return currentTime
        }
        let t = Double(frame) / f.processingFormat.sampleRate
        return max(0, min(t, duration))
    }

    private func startTicking() {
        stopTicking()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            self.currentTime = self.computeCurrentTime()
        }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: 8D

    private func updatePanTimer() {
        let shouldRun = settings.eightDOn && isPlaying
        if shouldRun {
            if panTimer == nil {
                let interval = 1.0 / 30.0
                let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    let cycle = Double(max(self.settings.eightDCycle, 1)) / Double(max(self.settings.effectiveSpeed, 0.1))
                    self.panPhase += interval / cycle * 2 * Double.pi
                    if self.panPhase > 2 * Double.pi { self.panPhase -= 2 * Double.pi }
                    self.panMixer.pan = Float(sin(self.panPhase)) * 0.95
                }
                RunLoop.main.add(t, forMode: .common)
                panTimer = t
            }
        } else {
            panTimer?.invalidate()
            panTimer = nil
            if !settings.eightDOn { panMixer.pan = 0 }
        }
    }

    // MARK: Now playing / remote

    private func loadArtwork(for track: Track) {
        if let img = Library.artworkImage(for: track) {
            currentArtwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        } else {
            currentArtwork = nil
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let speed = Double(settings.effectiveSpeed)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: settings.slowedOn ? "\(track.title) (slowed)" : track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: speed
        ]
        if let art = currentArtwork {
            info[MPMediaItemPropertyArtwork] = art
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            self?.play(); return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            self?.pause(); return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause(); return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.next(); return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous(); return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }

    // MARK: Notifications

    private func handleInterruption(_ n: Notification) {
        guard let info = n.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        DispatchQueue.main.async {
            switch type {
            case .began:
                if self.isPlaying { self.pause() }
            case .ended:
                if let optValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let opts = AVAudioSession.InterruptionOptions(rawValue: optValue)
                    if opts.contains(.shouldResume) { self.play() }
                }
            @unknown default:
                break
            }
        }
    }

    private func handleRouteChange(_ n: Notification) {
        guard let info = n.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable {
            DispatchQueue.main.async {
                if self.isPlaying { self.pause() }
            }
        }
    }

    private func handleEngineConfigChange(_ n: Notification) {
        DispatchQueue.main.async {
            guard self.file != nil else { return }
            let wasPlaying = self.isPlaying
            let t = self.currentTime
            self.isPlaying = false
            self.seek(to: t)
            if wasPlaying { self.play() }
        }
    }
}
