import AppKit

enum PasteboardAttachmentDetector {
    static let heicType = NSPasteboard.PasteboardType("public.heic")
    static let heifType = NSPasteboard.PasteboardType("public.heif")
    static let jpegType = NSPasteboard.PasteboardType("public.jpeg")
    static let qtImagePNGType = NSPasteboard.PasteboardType("com.trolltech.anymime.image--png")
    static let publicImageType = NSPasteboard.PasteboardType("public.image")

    static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        heicType,
        heifType,
        jpegType,
        qtImagePNGType,
        publicImageType
    ]

    static let rawImageTypePairs: [(NSPasteboard.PasteboardType, String)] = [
        (.png, "image/png"),
        (.tiff, "image/tiff"),
        (heicType, "image/heic"),
        (heifType, "image/heif"),
        (jpegType, "image/jpeg"),
        (qtImagePNGType, "image/png"),
        (publicImageType, "image/png")
    ]

    static func isAttachmentType(_ type: NSPasteboard.PasteboardType) -> Bool {
        if imagePasteboardTypes.contains(type) || type == .fileURL || type == .URL {
            return true
        }
        return looksLikeImageType(type)
    }

    static func hasAttachments(on pasteboard: NSPasteboard = .general) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) {
            return true
        }

        if let types = pasteboard.types,
           types.contains(where: { isAttachmentType($0) }) {
            return true
        }

        if pasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
            return true
        }

        if let items = pasteboard.pasteboardItems {
            for item in items {
                for type in item.types where looksLikeImageType(type) {
                    if let data = item.data(forType: type), data.count > 32 {
                        return true
                    }
                }
            }
        }

        return false
    }

    static func looksLikeImageType(_ type: NSPasteboard.PasteboardType) -> Bool {
        let raw = type.rawValue.lowercased()
        if raw == "public.file-url" || raw == "public.url" { return false }
        return raw.contains("image")
            || raw.contains("png")
            || raw.contains("tiff")
            || raw.contains("jpeg")
            || raw.contains("jpg")
            || raw.contains("heic")
            || raw.contains("heif")
            || raw.contains("screenshot")
            || raw.contains("screen-capture")
    }
}
