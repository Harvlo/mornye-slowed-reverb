import UIKit
import UniformTypeIdentifiers

/// Presents UIDocumentPickerViewController directly from UIKit (more reliable than SwiftUI .fileImporter,
/// which can fail to deliver the selection when other sheets live in the same hierarchy).
final class ImportPicker: NSObject, UIDocumentPickerDelegate {
    static let shared = ImportPicker()
    private var onPick: (([URL]) -> Void)?

    static var audioTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        for ext in ["flac", "m4a", "aac", "caf", "opus", "ogg", "alac"] {
            if let t = UTType(filenameExtension: ext), !types.contains(t) { types.append(t) }
        }
        if let flac = UTType("org.xiph.flac"), !types.contains(flac) { types.append(flac) }
        for t in lyricsTypes where !types.contains(t) { types.append(t) }
        return types
    }

    static var lyricsTypes: [UTType] {
        var types: [UTType] = []
        if let lrc = UTType(filenameExtension: "lrc") { types.append(lrc) }
        types.append(.plainText)
        return types
    }

    func present(onPick: @escaping ([URL]) -> Void) {
        present(types: ImportPicker.audioTypes, multiple: true, onPick: onPick)
    }

    func present(types: [UTType], multiple: Bool, onPick: @escaping ([URL]) -> Void) {
        self.onPick = onPick
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        guard let top = ImportPicker.topViewController() else { return }
        top.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let handler = onPick
        onPick = nil
        handler?(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onPick = nil
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        guard let root = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
