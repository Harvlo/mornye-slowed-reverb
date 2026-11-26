import SwiftUI

enum EffectsMode {
    case all, slowed, equalizer
}

struct EffectsView: View {
    @EnvironmentObject var player: AudioPlayer
    @State private var confirmReset = false
    var mode: EffectsMode = .all

    private var title: LocalizedStringKey {
        switch mode {
        case .all: return "Efectos"
        case .slowed: return "Slowed + Reverb"
        case .equalizer: return "Ecualizador y efectos"
        }
    }

    var body: some View {
        Form {
            if mode != .equalizer { slowedSection }
            if mode != .slowed {
                eqSection
                extrasSection
            }
            Section {
                Button(role: .destructive) { confirmReset = true } label: {
                    Label(mode == .all ? LocalizedStringKey("Restablecer todos los efectos") : LocalizedStringKey("Restablecer"),
                          systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle(title)
        .confirmationDialog("¿Restablecer todos los efectos?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Restablecer", role: .destructive) { reset() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func reset() {
        let d = EffectSettings()
        switch mode {
        case .all:
            player.resetEffects()
        case .slowed:
            var s = player.settings
            s.slowedOn = d.slowedOn; s.speed = d.speed; s.keepPitch = d.keepPitch
            s.pitchSemitones = d.pitchSemitones; s.reverbMix = d.reverbMix; s.reverbRoom = d.reverbRoom
            player.settings = s
        case .equalizer:
            var s = player.settings
            s.eqOn = d.eqOn; s.eqGains = d.eqGains; s.eqPresetName = d.eqPresetName; s.bassBoost = d.bassBoost
            s.eightDOn = d.eightDOn; s.eightDCycle = d.eightDCycle
            s.echoOn = d.echoOn; s.echoTime = d.echoTime; s.echoFeedback = d.echoFeedback; s.echoMix = d.echoMix
            s.underwaterOn = d.underwaterOn; s.underwaterCutoff = d.underwaterCutoff
            player.settings = s
        }
    }

    // MARK: Slowed + Reverb

    private var slowedSection: some View {
        Section {
            Toggle(isOn: $player.settings.slowedOn) {
                Label {
                    Text("Slowed + Reverb").font(.headline)
                } icon: {
                    Image(systemName: "tortoise.fill").foregroundColor(Theme.accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EffectSettings.speedPresets, id: \.self) { name in
                        Button {
                            player.settings.applySpeedPreset(name)
                        } label: {
                            Text(LocalizedStringKey(name))
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundColor(Theme.accent)
                                .glassCard(shape: .capsule, tint: isGlassAvailable ? nil : Theme.accent.opacity(0.2), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            ValueSlider(title: "Velocidad", value: $player.settings.speed, range: 0.5...1.5, step: 0.01,
                        format: { String(format: "%.2fx", $0) })
            Toggle("Mantener tono (sin efecto vinilo)", isOn: $player.settings.keepPitch)
            ValueSlider(title: "Tono extra", value: $player.settings.pitchSemitones, range: -12...12, step: 0.5,
                        format: { String(format: "%+.1f st", $0) })
            ValueSlider(title: "Reverb", value: $player.settings.reverbMix, range: 0...100, step: 1,
                        format: { "\(Int($0))%" })
            Picker("Sala", selection: $player.settings.reverbRoom) {
                ForEach(0..<ReverbRoom.all.count, id: \.self) { i in
                    Text(LocalizedStringKey(ReverbRoom.all[i].name)).tag(i)
                }
            }
        } header: {
            Text("Lo más importante")
        } footer: {
            Text("En modo vinilo el tono baja junto con la velocidad, como en los vídeos slowed. Activa «Mantener tono» si solo quieres cambiar la velocidad.")
        }
    }

    // MARK: EQ

    private var eqSection: some View {
        Section {
            Toggle(isOn: $player.settings.eqOn) {
                Label("Ecualizador", systemImage: "slider.vertical.3")
            }
            Picker("Preset", selection: Binding(
                get: { player.settings.eqPresetName },
                set: { name in
                    if let p = EQPreset.all.first(where: { $0.name == name }) {
                        player.settings.eqGains = p.gains
                        player.settings.eqPresetName = name
                        player.settings.eqOn = true
                    }
                }
            )) {
                ForEach(EQPreset.all.map { $0.name } + ["Personalizado"], id: \.self) { name in
                    Text(LocalizedStringKey(name)).tag(name)
                }
            }
            EQBandsView()
            ValueSlider(title: "Bass boost", value: $player.settings.bassBoost, range: 0...12, step: 0.5,
                        format: { String(format: "+%.1f dB", $0) })
        } header: {
            Text("Ecualizador de 10 bandas")
        }
    }

    // MARK: Extras

    private var extrasSection: some View {
        Section {
            Toggle(isOn: $player.settings.eightDOn) {
                Label("Audio 8D", systemImage: "headphones")
            }
            if player.settings.eightDOn {
                ValueSlider(title: "Vuelta cada", value: $player.settings.eightDCycle, range: 2...16, step: 0.5,
                            format: { String(format: "%.1f s", $0) })
            }

            Toggle(isOn: $player.settings.echoOn) {
                Label("Eco", systemImage: "dot.radiowaves.left.and.right")
            }
            if player.settings.echoOn {
                ValueSlider(title: "Tiempo", value: $player.settings.echoTime, range: 0.05...1.5, step: 0.01,
                            format: { String(format: "%.2f s", $0) })
                ValueSlider(title: "Repeticiones", value: $player.settings.echoFeedback, range: 0...85, step: 1,
                            format: { "\(Int($0))%" })
                ValueSlider(title: "Mezcla", value: $player.settings.echoMix, range: 0...100, step: 1,
                            format: { "\(Int($0))%" })
            }

            Toggle(isOn: $player.settings.underwaterOn) {
                Label("Bajo el agua", systemImage: "drop.fill")
            }
            if player.settings.underwaterOn {
                ValueSlider(title: "Corte", value: $player.settings.underwaterCutoff, range: 200...3000, step: 10,
                            format: { "\(Int($0)) Hz" })
            }
        } header: {
            Text("Efectos extra")
        } footer: {
            Text("El 8D funciona mejor con auriculares.")
        }
    }
}

struct EQBandsView: View {
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<10, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(EQPreset.labels[i])
                        .font(.caption.monospacedDigit())
                        .frame(width: 34, alignment: .leading)
                        .foregroundColor(.secondary)
                    Slider(value: gainBinding(i), in: -12...12, step: 0.5)
                    Text(String(format: "%+.1f", gain(i)))
                        .font(.caption.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        .opacity(player.settings.eqOn ? 1 : 0.45)
    }

    private func gain(_ i: Int) -> Float {
        let g = player.settings.eqGains
        return i < g.count ? g[i] : 0
    }

    private func gainBinding(_ i: Int) -> Binding<Float> {
        Binding(
            get: { gain(i) },
            set: { value in
                var g = player.settings.eqGains
                while g.count < 10 { g.append(0) }
                g[i] = value
                player.settings.eqGains = g
                player.settings.eqPresetName = "Personalizado"
                if !player.settings.eqOn { player.settings.eqOn = true }
            }
        )
    }
}

struct ValueSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let format: (Float) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundColor(Theme.accent)
            }
            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 2)
    }
}
