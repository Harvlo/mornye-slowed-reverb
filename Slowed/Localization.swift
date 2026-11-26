import Foundation

/// In-app language override. "system" follows the device language.
enum AppLanguage {
    static let storageKey = "appLanguage"

    struct Option: Hashable {
        let code: String
        let name: String
    }

    static let options: [Option] = [
        Option(code: "system", name: "Sistema"),
        Option(code: "es", name: "Español"),
        Option(code: "en", name: "English"),
        Option(code: "pt", name: "Português"),
        Option(code: "fr", name: "Français"),
        Option(code: "it", name: "Italiano"),
        Option(code: "de", name: "Deutsch"),
        Option(code: "ja", name: "日本語")
    ]

    static var current: String {
        UserDefaults.standard.string(forKey: storageKey) ?? "system"
    }

    /// Language actually used for lookups (resolves "system" against the app's localizations).
    static var resolved: String {
        if current != "system" { return current }
        return Bundle.main.preferredLocalizations.first ?? "es"
    }

    static var bundle: Bundle {
        if let path = Bundle.main.path(forResource: resolved, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b
        }
        return Bundle.main
    }

    static var locale: Locale {
        current == "system" ? Locale.autoupdatingCurrent : Locale(identifier: current)
    }

    static func set(_ code: String) {
        UserDefaults.standard.set(code, forKey: storageKey)
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }
}

/// Localized string for non-SwiftUI code (messages, alerts, lock screen).
func L(_ key: String) -> String {
    AppLanguage.bundle.localizedString(forKey: key, value: key, table: nil)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: AppLanguage.locale, arguments: args)
}
