import SwiftUI
import AVKit

struct PlayerView: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showQueue = false
    @State private var showSlowed = false
    @State private var showEQ = false
    @State private var showLyrics = false

    var body: some View {
        let track = player.currentTrack
        let bg = Color(ArtworkColor.background(for: track))
        let accent = Color(ArtworkColor.accent(for: track))
        GeometryReader { geo in
            ZStack(alignment: .top) {
                bg.ignoresSafeArea()
                artwork(track, width: geo.size.width, height: (geo.size.height + geo.safeAreaInsets.top) * 0.58, bg: bg)
                    .ignoresSafeArea(edges: .top)
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    info(track)
                    progress(accent: accent)
                        .padding(.top, 18)
                    controls(accent: accent)
                        .padding(.top, 24)
                    bottomRow(accent: accent)
                        .padding(.top, 26)
                        .padding(.bottom, 10)
                }
                .padding(.horizontal, 24)
            }
        }
        .foregroundColor(.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.35), value: track?.id)
        .sheet(isPresented: $showQueue) {
            QueueView().environmentObject(player)
        }
        .sheet(isPresented: $showSlowed) {
            effectsSheet(.slowed) { showSlowed = false }
        }
        .sheet(isPresented: $showEQ) {
            effectsSheet(.equalizer) { showEQ = false }
        }
        .fullScreenCover(isPresented: $showLyrics) {
            LyricsView()
                .environmentObject(player)
        }
    }

    private func effectsSheet(_ mode: EffectsMode, close: @escaping () -> Void) -> some View {
        NavigationStack {
            EffectsView(mode: mode)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { close() }
                    }
                }
        }
        .environmentObject(player)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Artwork

    @ViewBuilder
    private func artwork(_ track: Track?, width: CGFloat, height: CGFloat, bg: Color) -> some View {
        ZStack(alignment: .bottom) {
            if let t = track, let img = Library.artworkImage(for: t) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                ZStack {
                    Theme.gradient
                    Image(systemName: "music.note")
                        .font(.system(size: width * 0.3, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(width: width, height: height)
            }
            LinearGradient(colors: [bg.opacity(0), bg.opacity(0.7), bg],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: height * 0.42)
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
        }
        .frame(width: width, height: height)
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            Text("Reproduciendo")
                .font(.headline)
            HStack(spacing: 4) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Cerrar"))
                Spacer()
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Cola"))
                moreMenu
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.35), radius: 6)
        .padding(.top, 4)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                player.settings.slowedOn.toggle()
            } label: {
                Label(player.settings.slowedOn ? LocalizedStringKey("Desactivar Slowed + Reverb") : LocalizedStringKey("Activar Slowed + Reverb"),
                      systemImage: "tortoise")
            }
            Button { showSlowed = true } label: {
                Label("Ajustar Slowed + Reverb", systemImage: "tortoise.fill")
            }
            Button { showEQ = true } label: {
                Label("Ecualizador y efectos", systemImage: "slider.vertical.3")
            }
            Divider()
            Button { showLyrics = true } label: {
                Label("Letra", systemImage: "quote.bubble")
            }
            Button { showQueue = true } label: {
                Label("Cola", systemImage: "list.bullet")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 19, weight: .bold))
                .rotationEffect(.degrees(90))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text("Más"))
    }

    // MARK: Info

    @ViewBuilder
    private func info(_ track: Track?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let track = track {
                HStack(spacing: 8) {
                    Text(track.title)
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(1)
                    if track.explicit {
                        Image(systemName: "e.square.fill")
                            .font(.system(size: 19))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                Text(track.artist)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)
            } else {
                Text("Nada en reproducción").font(.system(size: 28, weight: .bold))
                Text("Elige una canción de tu biblioteca").foregroundColor(.white.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Progress

    private func progress(accent: Color) -> some View {
        let shown = scrubbing ? scrubValue : player.currentTime
        return VStack(spacing: 10) {
            ThickSlider(value: shown, maxValue: max(player.duration, 0.1), active: scrubbing, accent: accent) { editing, value in
                scrubValue = value
                if editing {
                    scrubbing = true
                } else {
                    player.seek(to: value)
                    scrubbing = false
                }
            }
            ZStack {
                HStack {
                    Text(formatTime(shown))
                    Spacer()
                    Text(formatTime(player.duration))
                }
                .font(.footnote.monospacedDigit().weight(.semibold))
                .foregroundColor(.white.opacity(0.6))
                if !player.formatInfo.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .font(.caption2.weight(.bold))
                        Text(verbatim: player.formatInfo)
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassCard(shape: .capsule, tint: isGlassAvailable ? nil : Color.white.opacity(0.14))
                }
            }
        }
    }

    // MARK: Controls

    private func controls(accent: Color) -> some View {
        let muted = isGlassAvailable ? accent.opacity(0.18) : accent.opacity(0.16)
        return GlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 84, height: 66)
                        .background(isGlassAvailable ? Color.clear : Color.white.opacity(0.08))
                        .glassCard(cornerRadius: 20, tint: muted, interactive: true)
                }
                .accessibilityLabel(Text("Anterior"))
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(Color.black.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 66)
                        .background(isGlassAvailable ? Color.clear : accent)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .glassCard(cornerRadius: 22, tint: accent, interactive: true, fallback: false)
                }
                .accessibilityLabel(Text(player.isPlaying ? LocalizedStringKey("Pausa") : LocalizedStringKey("Reproducir")))
                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 84, height: 66)
                        .background(isGlassAvailable ? Color.clear : Color.white.opacity(0.08))
                        .glassCard(cornerRadius: 20, tint: muted, interactive: true)
                }
                .accessibilityLabel(Text("Siguiente"))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Bottom row

    private func smallButton(_ systemName: String, on: Bool = false, accent: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(on ? accent : .white.opacity(0.85))
            .frame(width: 46, height: 42)
            .background(isGlassAvailable ? Color.clear : Color.white.opacity(0.06))
            .glassCard(cornerRadius: 12, tint: isGlassAvailable ? nil : Color.white.opacity(0.1), interactive: true)
    }

    private func bottomRow(accent: Color) -> some View {
        HStack(spacing: 0) {
            Button { showLyrics = true } label: { smallButton("quote.bubble", accent: accent) }
                .accessibilityLabel(Text("Letra"))
            Spacer(minLength: 6)
            Button { showSlowed = true } label: {
                smallButton(player.settings.slowedOn ? "tortoise.fill" : "tortoise", on: player.settings.slowedOn, accent: accent)
                    .overlay(alignment: .topTrailing) {
                        if player.settings.slowedOn {
                            Circle().fill(accent).frame(width: 7, height: 7).offset(x: -5, y: 5)
                        }
                    }
            }
            .accessibilityLabel(Text("Slowed + Reverb"))
            Spacer(minLength: 6)
            HStack(spacing: 0) {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(player.shuffle ? accent : .white.opacity(0.85))
                        .frame(width: 48, height: 42)
                }
                .accessibilityLabel(Text("Aleatorio"))
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 20)
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(player.repeatMode == .off ? .white.opacity(0.85) : accent)
                        .frame(width: 48, height: 42)
                }
                .accessibilityLabel(Text("Repetir"))
            }
            .background(isGlassAvailable ? Color.clear : Color.white.opacity(0.06))
            .glassCard(cornerRadius: 12, tint: isGlassAvailable ? nil : Color.white.opacity(0.1), interactive: true)
            Spacer(minLength: 6)
            Button { showEQ = true } label: {
                smallButton("slider.vertical.3", on: player.settings.eqOn || player.settings.bassBoost > 0 || player.settings.eightDOn || player.settings.echoOn || player.settings.underwaterOn, accent: accent)
            }
            .accessibilityLabel(Text("Ecualizador y efectos"))
            Spacer(minLength: 6)
            AirPlayButton()
                .frame(width: 46, height: 42)
                .background(isGlassAvailable ? Color.clear : Color.white.opacity(0.06))
                .glassCard(cornerRadius: 12, tint: isGlassAvailable ? nil : Color.white.opacity(0.1), interactive: true)
                .accessibilityLabel(Text("AirPlay"))
        }
        .buttonStyle(.plain)
    }
}

/// Thick rounded progress bar with a vertical bar thumb and drag-to-seek.
struct ThickSlider: View {
    let value: Double
    let maxValue: Double
    let active: Bool
    var accent: Color = Theme.accent
    let onChange: (Bool, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = maxValue > 0 ? min(max(value / maxValue, 0), 1) : 0
            let barHeight: CGFloat = active ? 14 : 10
            let x = w * CGFloat(frac)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                    .frame(height: barHeight)
                Capsule().fill(accent)
                    .frame(width: max(x, barHeight), height: barHeight)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 4, height: barHeight + 12)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: min(max(x - 2, 0), w - 4))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(max(g.location.x / max(w, 1), 0), 1)
                        onChange(true, Double(f) * maxValue)
                    }
                    .onEnded { g in
                        let f = min(max(g.location.x / max(w, 1), 0), 1)
                        onChange(false, Double(f) * maxValue)
                    }
            )
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: 28)
    }
}

/// AirPlay / audio route picker.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor(Theme.accent)
        v.prioritizesVideoDevices = false
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct QueueView: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
                    HStack {
                        TrackRow(track: track, isCurrent: index == player.currentIndex, isPlaying: player.isPlaying)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { player.jump(to: index) }
                }
                .onDelete { player.removeFromQueue(at: $0) }
                .onMove { player.moveInQueue(from: $0, to: $1) }
            }
            .navigationTitle("Cola")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .overlay {
                if player.queue.isEmpty {
                    Text("La cola está vacía").foregroundColor(.secondary)
                }
            }
        }
    }
}
