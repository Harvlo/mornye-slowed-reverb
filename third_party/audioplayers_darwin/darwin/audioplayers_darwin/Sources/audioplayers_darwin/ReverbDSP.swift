import Foundation

/// Schroeder reverb for the Darwin playback tap. Freeverb's comb and allpass
/// layout (Jezar at Dreampoint, public domain), scaled to the stream rate.
/// Speed is not changed here: AVPlayer's varispeed rate does that, and this
/// processor always emits one sample per input sample so gapless handoff and
/// AutoMix keep their clocks.
///
/// The render callback never waits on [lock]. The caller holds it.
final class ReverbDSP {
  /// Reference types so the render thread can update delay state without
  /// copying a buffer on every sample.
  final class Comb {
    var buffer: [Double]
    var index = 0
    var filterstore = 0.0
    var feedback = 0.84
    var damp = 0.2

    init(length: Int) {
      buffer = [Double](repeating: 0, count: max(1, length))
    }

    func process(_ input: Double) -> Double {
      let output = buffer[index]
      filterstore = output * (1 - damp) + filterstore * damp
      var next = input + filterstore * feedback
      if abs(next) < 1e-20 { next = 0 }
      if abs(next) > 8 { next = next > 0 ? 8 : -8 }
      buffer[index] = next
      index += 1
      if index == buffer.count { index = 0 }
      return output
    }
  }

  final class Allpass {
    var buffer: [Double]
    var index = 0

    init(length: Int) {
      buffer = [Double](repeating: 0, count: max(1, length))
    }

    func process(_ input: Double) -> Double {
      let buffered = buffer[index]
      let output = -input + buffered
      buffer[index] = input + buffered * 0.5
      index += 1
      if index == buffer.count { index = 0 }
      return output
    }
  }

  /// Freeverb delay lengths at 44.1 kHz.
  static let combBase = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
  static let allpassBase = [225, 556, 441, 341]

  let lock = NSLock()
  private(set) var enabled = false
  private var mix = 0.4
  private var room = 0.55
  private var currentMix = 0.0
  private var rate = 44100.0
  private var combs = [[Comb]]()
  private var allpasses = [[Allpass]]()

  func configure(enabled: Bool, mix: Double, room: Double) {
    lock.lock()
    defer { lock.unlock() }
    self.enabled = enabled
    self.mix = min(1, max(0, mix.isFinite ? mix : 0.4))
    self.room = min(1, max(0, room.isFinite ? room : 0.55))
    retune()
  }

  func prepare(sampleRate: Double) {
    lock.lock()
    defer { lock.unlock() }
    rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 44100
    currentMix = 0
    combs = (0..<2).map { channel in
      Self.combBase.map { Comb(length: Self.scaled($0, channel: channel, rate: rate)) }
    }
    allpasses = (0..<2).map { channel in
      Self.allpassBase.map { Allpass(length: Self.scaled($0, channel: channel, rate: rate)) }
    }
    retune()
  }

  /// Caller holds [lock]. One frame, in place. Disabled, or a settled dry mix,
  /// leaves the frame untouched.
  func processFrame(_ frame: inout [Double], channels: Int) {
    guard enabled, channels > 0, frame.count >= channels, !combs.isEmpty else { return }
    let step = min(1, 1 / (rate * 0.03))
    currentMix += (mix - currentMix) * step
    if currentMix < 1e-5 && mix == 0 { return }
    let wet = currentMix * 3
    let dry = 1 - currentMix
    let gain = 0.015
    if channels == 1 {
      let input = frame[0].isFinite ? frame[0] : 0
      frame[0] = limit(dry * input + wet * reverberate(input * gain, channel: 0))
      return
    }
    let left = frame[0].isFinite ? frame[0] : 0
    let right = frame[1].isFinite ? frame[1] : 0
    frame[0] = limit(dry * left + wet * reverberate(left * gain, channel: 0))
    frame[1] = limit(dry * right + wet * reverberate(right * gain, channel: 1))
  }

  private func reverberate(_ input: Double, channel: Int) -> Double {
    var sum = 0.0
    for filter in combs[channel] { sum += filter.process(input) }
    var value = sum
    for filter in allpasses[channel] { value = filter.process(value) }
    return value
  }

  private func retune() {
    let feedback = 0.7 + room * 0.28
    let damp = 0.05 + (1 - room) * 0.4
    for channel in combs.indices {
      for index in combs[channel].indices {
        combs[channel][index].feedback = feedback
        combs[channel][index].damp = damp
      }
    }
  }

  private func limit(_ value: Double) -> Double {
    if !value.isFinite { return 0 }
    if abs(value) <= 1 { return value }
    let sign = value < 0 ? -1.0 : 1.0
    return sign * (1 - exp(1 - abs(value)))
  }

  private static func scaled(_ base: Int, channel: Int, rate: Double) -> Int {
    let spread = channel == 1 ? 23.0 : 0
    return max(1, Int((Double(base) + spread) * rate / 44100))
  }
}
