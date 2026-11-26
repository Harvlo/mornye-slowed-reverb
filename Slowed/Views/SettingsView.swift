import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: Int = 0
    @AppStorage(AppLanguage.storageKey) private var language: String = "system"
    @EnvironmentObject var library: Library

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tema", selection: $appearance) {
                        Text("Sistema").tag(0)
                        Text("Oscuro").tag(1)
                        Text("Claro").tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Apariencia")
                } footer: {
                    Text("«Sistema» sigue el modo claro u oscuro del iPhone.")
                }

                Section {
                    Picker("Idioma", selection: Binding(
                        get: { language },
                        set: { code in
                            AppLanguage.set(code)
                            language = code
                        }
                    )) {
                        ForEach(AppLanguage.options, id: \.code) { option in
                            if option.code == "system" {
                                Text("Sistema").tag(option.code)
                            } else {
                                Text(verbatim: option.name).tag(option.code)
                            }
                        }
                    }
                } header: {
                    Text("Idioma")
                } footer: {
                    Text("«Sistema» usa el idioma del iPhone. Algunos textos del sistema cambian al reiniciar la app.")
                }

                Section {
                    Label("Pulsa + en la Biblioteca para importar desde Archivos.", systemImage: "plus.circle")
                    Label("O copia canciones en Archivos › En mi iPhone › Slowed.", systemImage: "folder")
                    Label("Desde otra app: Compartir › Abrir en Slowed.", systemImage: "square.and.arrow.up")
                    Button {
                        library.refresh()
                        library.lastMessage = L("Biblioteca actualizada")
                    } label: {
                        Label("Buscar canciones nuevas", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("Añadir música")
                }

                Section {
                    Label("Mantén pulsada una canción › «Exportar con efectos» para guardar una copia slowed + reverb y compartirla.", systemImage: "square.and.arrow.up.on.square")
                } header: {
                    Text("Exportar")
                }

                Section {
                    HStack {
                        Text("Canciones")
                        Spacer()
                        Text("\(library.tracks.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Versión")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Info")
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
