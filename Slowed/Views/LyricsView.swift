import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var player: AudioPlayer
    @ObservedObject private var store = LyricsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var activeIndex: Int = -1
    @State private var userScrolledAt: Date = .distantPast
    @State private var importError = false

    var body: some View {
        let track = player.currentTrack
        let bg = Color(ArtworkColor.background(for: track))
        ZStack {
            LinearGradient(colors: [bg, bg.opacity(0.85), Color.black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header(track)
                content
                miniControls
            }
        }
        .foregroundColor(.white)
        .environment(\.colorScheme, .dark)
        .onAppear { store.load(for: track) }
        .alert("Letra", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No se pudo leer el archivo de letra.")
        }
    }

    private func header(_ track: Track?) -> some View {
        HStack(spacing: 12) {
            ArtworkView(track: track, size: 48, corner: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(track?.title ?? "").font(.headline).lineLimit(1)
                Text(track?.artist ?? "").font(.subheadline).foregroundColor(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            Menu {
                Button { importLRC() } label: { Label("Importar .lrc", systemImage: "doc.badge.plus") }
                Button { store.reloadCurrent() } label: { Label("Volver a buscar", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .glassCard(shape: .circle, tint: isGlassAvailable ? nil : Color.white.opacity(0.14), interactive: true)
            }
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .glassCard(shape: .circle, tint: isGlassAvailable ? nil : Color.white.opacity(0.14), interactive: true)
            }
            .accessibilityLabel(Text("Cerrar"))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading {
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Buscando letra…").foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let lyrics = store.lyrics, !lyrics.isEmpty {
            if lyrics.synced {
                syncedView(lyrics)
            } else {
                plainView(lyrics)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "quote.bubble").font(.system(size: 44)).foregroundColor(.white.opacity(0.5))
                Text("Sin letra para esta canción").font(.title3.bold())
                Text("Añade un archivo .lrc con el mismo nombre que la canción, impórtalo aquí o activa las letras de internet en Ajustes.")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button { importLRC() } label: {
                    Label("Importar .lrc", systemImage: "doc.badge.plus").padding(.horizontal, 8).padding(.vertical, 4)
                }
                .glassButton(prominent: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func syncedView(_ lyrics: Lyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 120)
                    ForEach(lyrics.lines) { line in
                        let isActive = line.id == activeIndex
                        let isPast = line.id < activeIndex
                        Text(verbatim: line.text)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white.opacity(isActive ? 1 : (isPast ? 0.45 : 0.32)))
                            .scaleEffect(isActive ? 1.0 : 0.97, anchor: .leading)
                            .blur(radius: isActive || abs(line.id - activeIndex) > 6 ? 0 : 0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let t = line.time {
                                    player.seek(to: t)
                                    if !player.isPlaying { player.play() }
                                    activeIndex = line.id
                                }
                            }
                            .id(line.id)
                            .animation(.easeOut(duration: 0.3), value: activeIndex)
                    }
                    Color.clear.frame(height: 300)
                    Text(verbatim: L("Fuente: %@", lyrics.source))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 28)
            }
            .simultaneousGesture(DragGesture().onChanged { _ in userScrolledAt = Date() })
            .overlay {
                // Drives the highlight ~10x per second from the precise player position.
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    Color.clear
                        .onChange(of: context.date) { _ in
                            updateActive(lyrics, proxy: proxy)
                        }
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                updateActive(lyrics, proxy: proxy, animated: false, force: true)
            }
        }
    }

    private func updateActive(_ lyrics: Lyrics, proxy: ScrollViewProxy, animated: Bool = true, force: Bool = false) {
        // Small lead so the line lights up as it's sung; scaled by speed since song time moves slower/faster.
        let rate = Double(max(player.settings.effectiveSpeed, 0.1))
        let t = player.livePosition() + 0.15 * rate
        var idx = -1
        for line in lyrics.lines {
            if let lt = line.time, lt <= t { idx = line.id } else if line.time != nil { break }
        }
        guard idx != activeIndex || force else { return }
        activeIndex = idx
        // Don't fight the user while they scroll manually.
        guard Date().timeIntervalSince(userScrolledAt) > 3 || force else { return }
        let target = max(idx, 0)
        if animated {
            // Slower songs (slowed) get a slightly longer, softer scroll.
            withAnimation(.easeInOut(duration: min(0.6, 0.35 / rate))) {
                proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.35))
            }
        } else {
            proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.35))
        }
    }

    private func plainView(_ lyrics: Lyrics) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(lyrics.lines) { line in
                    Text(verbatim: line.text)
                        .font(.system(size: 24, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Letra sin sincronizar")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 20)
                Text(verbatim: L("Fuente: %@", lyrics.source))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
        }
    }

    private var miniControls: some View {
        HStack(spacing: 40) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 64, height: 64)
                    .background(isGlassAvailable ? Color.clear : Theme.accent)
                    .clipShape(Circle())
                    .glassCard(shape: .circle, tint: Theme.accent, interactive: true, fallback: false)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title2)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 14)
    }

    private func importLRC() {
        guard let track = player.currentTrack else { return }
        ImportPicker.shared.present(types: ImportPicker.lyricsTypes, multiple: false) { urls in
            guard let url = urls.first else { return }
            if !store.importLRC(from: url, for: track) { importError = true }
        }
    }
}
