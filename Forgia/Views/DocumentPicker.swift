import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Il selettore di file di UIKit, incartato per SwiftUI.
///
/// `.fileImporter` di SwiftUI, dentro un foglio, a volte chiama la sua chiusura
/// senza che l'aggiornamento di stato arrivi a destinazione: si tocca Apri e non
/// succede niente. Questo passa dal controller di sistema, che non ha quel
/// difetto.
///
/// `asCopy: true` fa consegnare a iOS una copia del file dentro la cartella
/// temporanea dell'app: niente risorse con permesso a scadenza, niente
/// `startAccessingSecurityScopedResource`.
struct DocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType] = [.item]
    var allowsMultipleSelection: Bool = true
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: DocumentPicker

        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
