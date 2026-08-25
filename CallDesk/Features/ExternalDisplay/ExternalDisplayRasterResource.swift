import SwiftUI
import UIKit

/// Loads the loose PNG resources used by the external display.
///
/// These images are copied into the application bundle rather than an asset
/// catalog. Resolving their file URLs avoids the named-image lookup used for
/// asset catalogs, which can return an empty image on a secondary display.
enum ExternalDisplayRasterResource {
    static func load(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }
}

/// A SwiftUI image wrapper for loose external-display PNG files.
struct ExternalDisplayRasterImage: View {
    let name: String

    var body: some View {
        if let image = ExternalDisplayRasterResource.load(named: name) {
            Image(uiImage: image)
                .resizable()
        } else {
            Color.clear
        }
    }
}
