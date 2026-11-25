import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var library: Library
    @Binding var showPlayer: Bool
    @State private var showImporter = false
    @State private var search = ""
    @State private var sortMode = 0 // 0 recientes, 1 titulo, 2 artista
    @State private var exporting: Track? = nil
    @State private var exportProgress: Double = 0
    @State private var exportResult: URL? = nil
    @State private var showShare = false
    @State private var editing: Track? = nil

    private var importTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        if let flac2 = UTType("org.xiph.flac") { types.append(flac2) }
        return types
    }

    private var visibleTracks: [Track] {
        var list = library.tracks
        switch sortMode {
        case 1: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case 2: list.sort { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        default: list.sort { $0.addedAt > $1.addedAt }
        }
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return list }
        return list.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Biblioteca")
            .searchable(text: $search, prompt: "Buscar canciones")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Ordenar", selection: $sortMode) {
                            Text("Recientes").tag(0)
                            Text("Título").tag(1)
                            Text("Artista").tag(2)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImporter = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: importTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    library.importFiles(urls)
                }
            }
            .safeAreaInset(edge: .bottom) { MiniPlayerBar(showPlayer: $showPlayer) }
            .overlay(alignment: .top) { toast }
            .overlay { exportOverlay }
            .sheet(isPresented: $showShare) {
                if let url = exportResult {
                    ShareSheet(items: [url])
                }
            }
            .sheet(item: $editing) { track in
                EditTrackView(track: track)
                    .environmentObject(library)
            }
            .refreshable { library.refresh() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 110, height: 110)
                Image(systemName: "waveform").font(.system(size: 46, weight: .bold)).foregroundColor(.white)
            }
            Text("Tu biblioteca está vacía").font(.title2.bold())
            Text("Importa canciones (MP3, M4A, WAV o FLAC) desde la app Archivos, o cópialas a la carpeta «Slowed» en Archivos › En mi iPhone.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button {
                showImporter = true
            } label: {
                Label("Importar canciones", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Theme.gradient)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        let tracks = visibleTracks
        return List {
            Section {
                HStack(spacing: 12) {
                    Button {
                        player.play(tracks: tracks, startAt: 0)
                        showPlayer = true
                    } label: {
                        Label("Reproducir", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        if !player.shuffle { player.toggleShuffle() }
                        if !tracks.isEmpty {
                            player.play(tracks: tracks, startAt: Int.random(in: 0..<tracks.count))
                            showPlayer = true
                        }
                    } label: {
                        Label("Aleatorio", systemImage: "shuffle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.accent)
                .font(.headline)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section(header: Text("\(tracks.count) canciones")) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, isCurrent: player.currentTrack?.id == track.id, isPlaying: player.isPlaying)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            player.play(tracks: tracks, startAt: index)
                        }
                        .contextMenu {
                            Button { player.playNext(track) } label: { Label("Reproducir a continuación", systemImage: "text.insert") }
                            Button { player.addToQueue(track) } label: { Label("Añadir a la cola", systemImage: "text.append") }
                            Button { startExport(track) } label: { Label("Exportar con efectos", systemImage: "square.and.arrow.up") }
                            Button { editing = track } label: { Label("Editar info", systemImage: "pencil") }
                            Button(role: .destructive) { delete(track) } label: { Label("Eliminar", systemImage: "trash") }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(track) } label: { Label("Eliminar", systemImage: "trash") }
                            Button { player.addToQueue(track) } label: { Label("Cola", systemImage: "text.append") }
                                .tint(Theme.accent)
                        }
                        .swipeActions(edge: .leading) {
                            Button { player.playNext(track) } label: { Label("Siguiente", systemImage: "text.insert") }
                                .tint(.orange)
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var toast: some View {
        if let msg = library.lastMessage {
            Text(msg)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 8)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        library.lastMessage = nil
                    }
                }
        }
    }

    @ViewBuilder
    private var exportOverlay: some View {
        if let track = exporting {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView(value: exportProgress)
                        .frame(width: 220)
                    Text("Exportando «\(track.title)»…").font(.headline).multilineTextAlignment(.center)
                    Text("\(Int(exportProgress * 100))%").font(.caption).foregroundColor(.secondary)
                }
                .padding(24)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(30)
            }
        }
    }

    private func delete(_ track: Track) {
        player.trackRemovedFromLibrary(track)
        library.delete(track)
    }

    private func startExport(_ track: Track) {
        let settings = player.settings
        exporting = track
        exportProgress = 0
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try Exporter.export(track: track, settings: settings) { p in
                    DispatchQueue.main.async { exportProgress = p }
                }
                DispatchQueue.main.async {
                    exporting = nil
                    library.refresh()
                    library.lastMessage = "Guardada en la biblioteca"
                    exportResult = url
                    showShare = true
                }
            } catch {
                DispatchQueue.main.async {
                    exporting = nil
                    player.errorMessage = "No se pudo exportar: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track, size: 46, corner: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body.weight(isCurrent ? .bold : .regular))
                    .foregroundColor(isCurrent ? Theme.accent : .primary)
                    .lineLimit(1)
                Text(track.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if isCurrent {
                Image(systemName: isPlaying ? "waveform" : "pause.circle")
                    .foregroundColor(Theme.accent)
            }
            Text(formatTime(track.duration)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct EditTrackView: View {
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var title = ""
    @State private var artist = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Título", text: $title)
                TextField("Artista", text: $artist)
            }
            .navigationTitle("Editar info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        library.rename(track, title: title, artist: artist)
                        dismiss()
                    }
                }
            }
            .onAppear {
                title = track.title
                artist = track.artist
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
