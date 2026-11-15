import Foundation

@main struct ReverbDSPTests {
  static func engine(enabled: Bool = true, mix: Double = 0.4, room: Double = 0.55) -> ReverbDSP {
    let engine = ReverbDSP()
    engine.configure(enabled: enabled, mix: mix, room: room)
    engine.prepare(sampleRate: 48000)
    return engine
  }

  static func render(_ engine: ReverbDSP, _ samples: [Double]) -> [Double] {
    engine.lock.lock()
    defer { engine.lock.unlock() }
    var output = [Double]()
    output.reserveCapacity(samples.count)
    for sample in samples {
      var frame = [sample, sample]
      engine.processFrame(&frame, channels: 2)
      assert(frame.allSatisfy { $0.isFinite })
      output.append(frame[0])
    }
    return output
  }

  static func energy(_ samples: ArraySlice<Double>) -> Double {
    samples.reduce(0) { $0 + abs($1) }
  }

  static func main() {
    let dry = engine(mix: 0, room: 0.2)
    let settled = render(dry, [Double](repeating: 0, count: 8000) + [0.25, -0.5, 0.8])
    assert(abs(settled[settled.count - 3] - 0.25) < 1e-6, "Dry mix must pass samples through")
    assert(abs(settled[settled.count - 2] + 0.5) < 1e-6)
    assert(abs(settled[settled.count - 1] - 0.8) < 1e-6)

    let bypass = engine(enabled: false, mix: 1, room: 1)
    let untouched = render(bypass, [0.2, -0.4])
    assert(untouched == [0.2, -0.4], "Disabled reverb must be transparent immediately")

    let wet = engine(mix: 1, room: 0.85)
    var impulse = [Double](repeating: 0, count: 4000)
    impulse.append(1)
    impulse.append(contentsOf: [Double](repeating: 0, count: 12000))
    let tail = render(wet, impulse)
    let early = energy(tail[(4000 + 400)..<(4000 + 2500)])
    let late = energy(tail[(4000 + 7000)..<(4000 + 10000)])
    assert(early > 0.05, "An impulse must leave a reverb tail")
    assert(early > late, "The tail must decay")

    var tone = [Double]()
    for index in 0..<48000 {
      tone.append(0.5 * sin(Double(index) * 2 * .pi * 220 / 48000))
    }
    let sustained = render(engine(mix: 0.65, room: 0.7), tone)
    assert(sustained.allSatisfy { abs($0) <= 1.01 }, "Sustained audio must stay inside the output ceiling")

    for rate in [44100.0, 96000.0, 192000.0] {
      let stress = ReverbDSP()
      stress.configure(enabled: true, mix: 1, room: 1)
      stress.prepare(sampleRate: rate)
      stress.lock.lock()
      for sample in 0..<8000 {
        var frame = [sin(Double(sample) * 0.07), cos(Double(sample) * 0.05)]
        stress.processFrame(&frame, channels: 2)
        assert(frame.allSatisfy { $0.isFinite && abs($0) <= 1.01 })
      }
      stress.lock.unlock()
    }
    print("PASS: dry bypass, disabled bypass, decaying tail, ceiling and multi-rate stability")
  }
}
