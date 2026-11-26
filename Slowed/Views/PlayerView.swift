import SwiftUI
import AVKit

struct PlayerView: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showQueue = false
    @State private var showEffects = false
    @State private var showLyrics = false

    var body: some View {
        let track = player.currentTrack
        let bg = Color(ArtworkColor.background(for: track))
        GeometryReader { geo in
            ZStack(alignment: .top) {
                bg.ignoresSafeArea()
                artwork(track, width: geo.size.width, bg: bg)
                    .ignoresSafeArea(edges: .top)
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    info(track)
                    progress
                        .padding(.top, 18)
                    controls
                        .padding(.top, 22)
                    bottomRow
                        .padding(.top, 26)
                        .padding(.bottom, 8)
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
        .sheet(isPresented: $showEffects) {
            NavigationStack {
                EffectsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { showEffects = false }
                        }
                    }
            }
            .environmentObject(player)
        }
        .fullScreenCover(isPresented: $showLyrics) {
            LyricsView()
                .environmentObject(player)
        }
    }

    // MARK: Artwork

    @ViewBuilder
    private func artwork(_ track: Track?, width: CGFloat, bg: Color) -> some View {
        ZStack(alignment: .bottom) {
            if let t = track, let img = Library.artworkImage(for: t) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: width)
                    .clipped()
            } else {
                ZStack {
                    Theme.gradient
                    Image(systemName: "music.note")
                        .font(.system(size: width * 0.3, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .frame(width: width, height: width)
            }
            LinearGradient(colors: [bg.opacity(0), bg.opacity(0.65), bg],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: width * 0.45)
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [Color.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
        }
        .frame(width: width, height: width)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 40, height: 40)
                    .glassCard(shape: .circle, tint: isGlassAvailable ? nil : Color.black.opacity(0.25), interactive: true)
            }
            .accessibilityLabel(Text("Cerrar"))
            Spacer()
            Text("Reproduciendo")
                .font(.headline)
            Spacer()
            HStack(spacing: 10) {
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 40)
                        .glassCard(shape: .circle, tint: isGlassAvailable ? nil : Color.black.opacity(0.25), interactive: true)
                }
                .accessibilityLabel(Text("Cola"))
                moreMenu
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                player.settings.slowedOn.toggle()
            } label: {
                Label(player.settings.slowedOn ? LocalizedStringKey("Desactivar Slowed + Reverb") : LocalizedStringKey("Activar Slowed + Reverb"),
                      systemImage: "tortoise")
            }
            Menu {
                ForEach(EffectSettings.speedPresets, id: \.self) { name in
                    Button(LocalizedStringKey(name)) { player.settings.applySpeedPreset(name) }
                }
            } label: {
                Label("Presets de velocidad", systemImage: "speedometer")
            }
            Button { showEffects = true } label: {
                Label("Efectos y ecualizador", systemImage: "slider.horizontal.3")
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
                .font(.system(size: 16, weight: .bold))
                .rotationEffect(.degrees(90))
                .frame(width: 40, height: 40)
                .glassCard(shape: .circle, tint: isGlassAvailable ? nil : Color.black.opacity(0.25), interactive: true)
        }
        .accessibilityLabel(Text("Más"))
    }

    // MARK: Info

    @ViewBuilder
    private func info(_ track: Track?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if let track = track {
                    HStack(spacing: 8) {
                        Text(track.title)
                            .font(.system(size: 26, weight: .bold))
                            .lineLimit(1)
                        if track.explicit {
                            Image(systemName: "e.square.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    Text(track.artist)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                } else {
                    Text("Nada en reproducción").font(.system(size: 26, weight: .bold))
                    Text("Elige una canción de tu biblioteca").foregroundColor(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
            if player.settings.slowedOn {
                Text(String(format: "%.2fx", player.settings.speed))
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .glassCard(shape: .capsule, tint: Theme.accent.opacity(isGlassAvailable ? 0.6 : 0.9))
            }
        }
    }

    // MARK: Progress

    private var progress: some View {
        let shown = scrubbing ? scrubValue : player.currentTime
        return VStack(spacing: 8) {
            ThickSlider(value: shown, maxValue: max(player.duration, 0.1), active: scrubbing) { editing, value in
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
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(.white.opacity(0.6))
                if !player.formatInfo.isEmpty {
                    Text(verbatim: player.formatInfo)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .glassCard(shape: .capsule, tint: isGlassAvailable ? nil : Color.white.opacity(0.16))
                }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        GlassGroup(spacing: 14) {
            HStack(spacing: 14) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: 76, height: 64)
                        .glassCard(cornerRadius: 22, tint: isGlassAvailable ? nil : Color.white.opacity(0.14), interactive: true)
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(isGlassAvailable ? Color.clear : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .glassCard(cornerRadius: 22, tint: Theme.accent, interactive: true, fallback: false)
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: 76, height: 64)
                        .glassCard(cornerRadius: 22, tint: isGlassAvailable ? nil : Color.white.opacity(0.14), interactive: true)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Bottom row

    private var bottomRow: some View {
        HStack {
            Button { showLyrics = true } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .glassCard(shape: .circle, tint: isGlassAvailable ? nil : Color.white.opacity(0.12), interactive: true)
            }
            .accessibilityLabel(Text("Letra"))
            Spacer()
            HStack(spacing: 0) {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(player.shuffle ? Theme.accent : .white.opacity(0.85))
                        .frame(width: 54, height: 46)
                }
                .accessibilityLabel(Text("Aleatorio"))
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 22)
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(player.repeatMode == .off ? .white.opacity(0.85) : Theme.accent)
                        .frame(width: 54, height: 46)
                }
                .accessibilityLabel(Text("Repetir"))
            }
            .glassCard(shape: .capsule, tint: isGlassAvailable ? nil : Color.white.opacity(0.12), interactive: true)
            Spacer()
            Button { showEffects = true } label: {
                Image(systemName: player.settings.slowedOn ? "tortoise.fill" : "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(player.settings.slowedOn ? Theme.accent : .white)
                    .frame(width: 46, height: 46)
                    .glassCard(shape: .circle, tint: isGlassAvailable ? nil : Color.white.opacity(0.12), interactive: true)
            }
            .accessibilityLabel(Text("Efectos"))
            Spacer()
            AirPlayButton()
                .frame(width: 46, height: 46)
                .glassCard(shape: .circle, tint: isGlassAvailable ? nil : Color.white.opacity(0.12), interactive: true)
                .accessibilityLabel(Text("AirPlay"))
        }
        .buttonStyle(.plain)
    }
}

/// Thick rounded progress bar with drag-to-seek.
struct ThickSlider: View {
    let value: Double
    let maxValue: Double
    let active: Bool
    let onChange: (Bool, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = maxValue > 0 ? min(max(value / maxValue, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(Theme.accent)
                    .frame(width: max(w * CGFloat(frac), active ? 12 : 8))
            }
            .frame(height: active ? 14 : 9)
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
        .frame(height: 24)
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
