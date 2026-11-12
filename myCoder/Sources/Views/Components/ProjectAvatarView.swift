import SwiftUI
import AppKit

/// Loads a project's favicon/logo once and caches it by project path.
enum ProjectIconLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func loadIcon(for projectPath: String) async -> NSImage? {
        guard !projectPath.isEmpty else { return nil }

        let key = projectPath as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let url = ProjectIconDiscovery.iconURL(forProjectAt: projectPath) else {
                return nil
            }
            return NSImage(contentsOf: url)
        }.value

        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }
}

/// A circular project avatar: shows the project's own favicon/logo when one
/// exists in the project root, otherwise falls back to the colored badge.
struct ProjectAvatarView: View {
    let workspace: Workspace
    var size: CGFloat = 28
    let fallbackColor: Color
    var fallbackSymbol: String? = nil

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(fallbackColor.opacity(0.2))
                .frame(width: size, height: size)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: size - 8, height: size - 8)
                    .clipShape(Circle())
            } else if let fallbackSymbol {
                Image(systemName: fallbackSymbol)
                    .interfaceFont(size: size * 0.42)
                    .foregroundColor(fallbackColor)
            } else {
                Text("#")
                    .interfaceFont(size: size * 0.42, weight: .bold)
                    .foregroundColor(fallbackColor)
            }
        }
        .task(id: workspace.path) {
            image = await ProjectIconLoader.loadIcon(for: workspace.path)
        }
    }
}
