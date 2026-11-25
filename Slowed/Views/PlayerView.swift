import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var player: AudioPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showQueue = false
    @State private var showEffects = false

    var body: some View {
        let track = player.currentTrack
        ZStack {
            background(track)
            VStack(spacing: 20) {
                Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 40, height: 5).padding(.top, 8)

                Spacer(minLength: 0)

                ArtworkView(track: track, size: 290, corner: 24)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 30, x: 0, y: 12)
                    .scaleEffect(player.isPlaying ? 1.0 : 0.92)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.isPlaying)

                VStack(spacing: 4) {
                    Text(track?.title ?? "Nada en reproducción")
                        .font(.title2.bold()).lineLimit(1)
                    Text(track?.artist ?? "Elige una canción de tu biblioteca")
                        .font(.body).foregroundColor(.secondary).lineLimit(1)
                }
                .padding(.horizontal)

                progress

                controls

                slowedCard

                HStack {
                    Button { showEffects = true } label: {
                        Label("Efectos", systemImage: "slider.horizontal.3")
                    }
                    Spacer()
                    Button { showQueue = true } label: {
                        Label("Cola", systemImage: "list.bullet")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
        }
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
    }

    @ViewBuilder
    private func background(_ track: Track?) -> some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if let t = track, let img = Library.artworkImage(for: t) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .opacity(0.45)
            } else {
                LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent2.opacity(0.12), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }

    private var progress: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(
                get: { scrubbing ? scrubValue : player.currentTime },
                set: { scrubValue = $0 }
            ), in: 0...max(player.duration, 0.1), onEditingChanged: { editing in
                if editing {
                    scrubValue = player.currentTime
                    scrubbing = true
                } else {
                    player.seek(to: scrubValue)
                    scrubbing = false
                }
            })
            HStack {
                Text(formatTime(scrubbing ? scrubValue : player.currentTime))
                Spacer()
                if player.settings.slowedOn && player.settings.speed != 1 {
                    Text("dura \(formatTime(player.duration / Double(player.settings.speed)))")
                        .foregroundColor(Theme.accent)
                }
                Spacer()
                Text("-" + formatTime(max(player.duration - (scrubbing ? scrubValue : player.currentTime), 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 28)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundColor(player.shuffle ? Theme.accent : .secondary)
            }
            .frame(maxWidth: .infinity)
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            .frame(maxWidth: .infinity)
            Button { player.togglePlayPause() } label: {
                ZStack {
                    Circle().fill(Theme.gradient).frame(width: 74, height: 74)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }
            .frame(maxWidth: .infinity)
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            .frame(maxWidth: .infinity)
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundColor(player.repeatMode == .off ? .secondary : Theme.accent)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .padding(.horizontal, 12)
    }

    private var slowedCard: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    player.settings.slowedOn.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "tortoise.fill")
                    Text(player.settings.slowedOn ? "Slowed + Reverb activado" : "Activar Slowed + Reverb")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Group {
                        if player.settings.slowedOn {
                            Theme.gradient
                        } else {
                            LinearGradient(colors: [Color.secondary.opacity(0.18)], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .foregroundColor(player.settings.slowedOn ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if player.settings.slowedOn {
                HStack {
                    Image(systemName: "speedometer").foregroundColor(.secondary)
                    Slider(value: $player.settings.speed, in: 0.5...1.5, step: 0.01)
                    Text(String(format: "%.2fx", player.settings.speed))
                        .font(.caption.monospacedDigit().bold())
                        .frame(width: 46)
                }
                HStack {
                    Image(systemName: "sparkles").foregroundColor(.secondary)
                    Slider(value: $player.settings.reverbMix, in: 0...100, step: 1)
                    Text("\(Int(player.settings.reverbMix))%")
                        .font(.caption.monospacedDigit().bold())
                        .frame(width: 46)
                }
            }
        }
        .padding(.horizontal, 24)
    }
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
