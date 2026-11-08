import Foundation

/// Il plist che iOS scarica tramite `itms-services://` e che gli dice dove
/// prendere il pacchetto.
struct InstallManifest {
    var bundleIdentifier: String
    var version: String
    var title: String
    var packageURL: URL
    var displayImageURL: URL?
    var fullSizeImageURL: URL?

    var data: Data {
        var assets: [[String: String]] = [[
            "kind": "software-package",
            "url": packageURL.absoluteString
        ]]
        if let displayImageURL {
            assets.append(["kind": "display-image", "url": displayImageURL.absoluteString])
        }
        if let fullSizeImageURL {
            assets.append(["kind": "full-size-image", "url": fullSizeImageURL.absoluteString])
        }

        let plist: [String: Any] = [
            "items": [[
                "assets": assets,
                "metadata": [
                    "bundle-identifier": bundleIdentifier,
                    "bundle-version": version,
                    "kind": "software",
                    "title": title
                ]
            ]]
        ]

        return (try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )) ?? Data()
    }
}
