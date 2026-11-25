import SwiftUI
import UIKit

@main
struct SlowedApp: App {
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var library = Library.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance: Int = 0

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(library)
                .tint(Theme.accent)
                .onAppear { applyAppearance(appearance) }
                .onChange(of: appearance) { value in applyAppearance(value) }
                .onOpenURL { url in
                    library.importFiles([url])
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                library.refresh()
                applyAppearance(appearance)
            }
        }
    }
}

/// 0 = Sistema, 1 = Oscuro, 2 = Claro
func applyAppearance(_ value: Int) {
    let style: UIUserInterfaceStyle
    switch value {
    case 1: style = .dark
    case 2: style = .light
    default: style = .unspecified
    }
    for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene else { continue }
        for window in windowScene.windows {
            window.overrideUserInterfaceStyle = style
        }
    }
}
