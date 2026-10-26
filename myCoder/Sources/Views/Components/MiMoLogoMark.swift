import SwiftUI
import AppKit

/// Official Mi logo from `mimo-coder/assets/images/logo.png`.
struct MiMoLogoMark: View {
    var size: CGFloat = 140

    var body: some View {
        Group {
            if let image = MiMoLogoLoader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                // Fallback: render a visible placeholder so we know the loader failed
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.orange)
                    Text("MI")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityLabel(MiMoLogoSpec.markText)
    }
}

enum MiMoLogoLoader {
    static let resourceName = "myCoderMark"

    /// SPM resource-bundle file names, in decreasing preference.
    /// Target `myCoder` + product `myCoder` → `myCoder_myCoder.bundle`.
    static func candidateBundleNames() -> [String] {
        ["myCoder_myCoder.bundle"]
    }

    /// The bundle used to locate resource files.
    ///
    /// SPM packages resources into `<Target>_<Product>.bundle`, which is NOT
    /// `Bundle.main` for an executable target. We locate it dynamically.
    static var resourceBundle: Bundle {
        // Prefer the SPM-generated resource bundle
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/myCoder_myCoder.bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Resources/myCoder_myCoder.bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Resources/myCoder_myCoder.bundle"),
        ]
        for url in candidates {
            let b = Bundle(url: url)
            if b?.url(forResource: resourceName, withExtension: "png") != nil {
                return b ?? .main
            }
            if b?.url(forResource: resourceName, withExtension: "svg") != nil {
                return b ?? .main
            }
        }
        // Fallback to main bundle
        return .main
    }

    static var image: NSImage? {
        let bundle = resourceBundle
        // Prefer PNG, fall back to SVG, then NSImage(named:)
        if let url = bundle.url(forResource: resourceName, withExtension: "png") {
            if let img = NSImage(contentsOf: url) { return img }
        }
        if let url = bundle.url(forResource: resourceName, withExtension: "svg") {
            if let img = NSImage(contentsOf: url) { return img }
        }
        // Try all candidate bundles directly
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/myCoder_myCoder.bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Resources/myCoder_myCoder.bundle"),
        ]
        for url in candidates {
            let b = Bundle(url: url) ?? .main
            if let fileURL = b.url(forResource: resourceName, withExtension: "png"),
               let img = NSImage(contentsOf: fileURL) { return img }
            if let fileURL = b.url(forResource: resourceName, withExtension: "svg"),
               let img = NSImage(contentsOf: fileURL) { return img }
        }
        return NSImage(named: NSImage.Name(resourceName))
    }
}

enum MiMoLogoSpec {
    static let markText = "Mi logo"
}
