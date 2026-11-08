import Foundation
import UIKit

/// Sostituisce l'icona di un bundle .app prima della firma.
///
/// Le app moderne tengono le icone dentro `Assets.car`, che è compilato e non si
/// può riscrivere. iOS però guarda ancora i PNG sciolti dentro il bundle quando
/// l'Info.plist li elenca in `CFBundleIconFiles` e non c'è `CFBundleIconName` a
/// mandarlo sull'asset catalog. Quindi: si scrivono i PNG nelle misure giuste e
/// si riscrive quella parte di Info.plist.
enum IconPatcher {
    private struct Variant {
        let fileName: String
        let side: CGFloat
    }

    /// Le misure che iOS cerca, con i nomi che si aspetta.
    private static let variants: [Variant] = [
        Variant(fileName: "AppIcon29x29@2x.png", side: 58),
        Variant(fileName: "AppIcon29x29@3x.png", side: 87),
        Variant(fileName: "AppIcon40x40@2x.png", side: 80),
        Variant(fileName: "AppIcon40x40@3x.png", side: 120),
        Variant(fileName: "AppIcon60x60@2x.png", side: 120),
        Variant(fileName: "AppIcon60x60@3x.png", side: 180),
        Variant(fileName: "AppIcon76x76@2x~ipad.png", side: 152),
        Variant(fileName: "AppIcon83.5x83.5@2x~ipad.png", side: 167),
        Variant(fileName: "AppIcon1024x1024.png", side: 1024)
    ]

    private static let iPhoneBaseNames = ["AppIcon29x29", "AppIcon40x40", "AppIcon60x60"]
    private static let iPadBaseNames = ["AppIcon29x29", "AppIcon40x40", "AppIcon76x76", "AppIcon83.5x83.5"]

    enum IconError: LocalizedError {
        case unreadableImage
        case renderFailed
        case infoPlistUnreadable

        var errorDescription: String? {
            switch self {
            case .unreadableImage:     return "L'immagine scelta per l'icona non è leggibile."
            case .renderFailed:        return "Non riesco a generare l'icona nelle misure richieste."
            case .infoPlistUnreadable: return "L'Info.plist dell'app non è modificabile."
            }
        }
    }

    static func apply(imageAt source: URL, toAppBundle bundle: URL) throws {
        guard let image = UIImage(contentsOfFile: source.path) else {
            throw IconError.unreadableImage
        }

        for variant in variants {
            guard let png = square(image, side: variant.side) else {
                throw IconError.renderFailed
            }
            try png.write(to: bundle.appendingPathComponent(variant.fileName), options: .atomic)
        }

        try patchInfoPlist(at: bundle.appendingPathComponent("Info.plist"))
    }

    /// Ritaglia al centro e riempie il quadrato: le icone iOS non possono avere
    /// trasparenza, quindi si disegna su fondo pieno.
    private static func square(_ image: UIImage, side: CGFloat) -> Data? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))

            let size = image.size
            guard size.width > 0, size.height > 0 else { return }
            let scale = max(side / size.width, side / size.height)
            let width = size.width * scale
            let height = size.height * scale
            image.draw(in: CGRect(
                x: (side - width) / 2,
                y: (side - height) / 2,
                width: width,
                height: height
            ))
        }
    }

    private static func patchInfoPlist(at url: URL) throws {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let data = try? Data(contentsOf: url),
              var info = try PropertyListSerialization.propertyList(
                from: data, options: [], format: &format
              ) as? [String: Any]
        else { throw IconError.infoPlistUnreadable }

        func iconsDictionary(_ names: [String]) -> [String: Any] {
            ["CFBundlePrimaryIcon": [
                "CFBundleIconFiles": names,
                "UIPrerenderedIcon": false
            ]]
        }

        info["CFBundleIcons"] = iconsDictionary(iPhoneBaseNames)
        info["CFBundleIcons~ipad"] = iconsDictionary(iPadBaseNames)
        info["CFBundleIconFiles"] = iPhoneBaseNames

        // Finché c'è questa chiave iOS pesca l'icona dall'asset catalog
        // compilato e ignora i file sciolti.
        info.removeValue(forKey: "CFBundleIconName")
        info.removeValue(forKey: "CFBundleIconFile")

        let output = try PropertyListSerialization.data(
            fromPropertyList: info, format: format, options: 0
        )
        try output.write(to: url, options: .atomic)
    }
}
