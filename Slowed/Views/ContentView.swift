import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: Library
    @State private var showPlayer = false

    var body: some View {
        TabView {
            LibraryView(showPlayer: $showPlayer)
                .tabItem { Label("Biblioteca", systemImage: "music.note.list") }
            NavigationStack {
                EffectsView()
                    .safeAreaInset(edge: .bottom) { MiniPlayerBar(showPlayer: $showPlayer) }
            }
            .tabItem { Label("Efectos", systemImage: "slider.horizontal.3") }
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
        .sheet(isPresented: $showPlayer) {
            PlayerView()
                .environmentObject(player)
                .environmentObject(library)
        }
        .alert("Aviso", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { player.errorMessage = nil }
        } message: {
            Text(player.errorMessage ?? "")
        }
    }
}

struct ArtworkView: View {
    let track: Track?
    var size: CGFloat
    var corner: CGFloat = 10

    var body: some View {
        ZStack {
            if let t = track, let img = Library.artworkImage(for: t) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.gradient
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject var player: AudioPlayer
    @Binding var showPlayer: Bool

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                ArtworkView(track: track, size: 44, corner: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        if player.settings.slowedOn {
                            Text(String(format: "%.2fx", player.settings.speed))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.accent.opacity(0.25))
                                .clipShape(Capsule())
                        }
                        Text(track.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    player.settings.slowedOn.toggle()
                } label: {
                    Image(systemName: player.settings.slowedOn ? "tortoise.fill" : "tortoise")
                        .font(.title3)
                        .foregroundColor(player.settings.slowedOn ? Theme.accent : .secondary)
                }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassCard(cornerRadius: 20, interactive: true)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture { showPlayer = true }
        }
    }
}
