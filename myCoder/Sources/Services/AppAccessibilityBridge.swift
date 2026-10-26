import AppKit
import ApplicationServices

/// In-process accessibility bridge. It exposes the same tree VoiceOver sees, so
/// automation can press any button/menu item without hard-coded screen
/// coordinates. If macOS has not trusted the app for Accessibility, the tree is
/// empty and the error names the exact System Settings pane.
enum AppAccessibilityBridge {
    struct Entry {
        let element: AXUIElement
        let path: String
        let index: Int
        let role: String
        let title: String
        let description: String
        let identifier: String
        let value: String
        let enabled: Bool
        let children: Int
    }

    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    static func tree(maxDepth: Int, limit: Int) -> [String: Any] {
        activate()
        guard AXIsProcessTrusted() else {
            return [
                "trusted": false,
                "error": "Accessibility permission is not granted to myCoder",
                "hint": "System Settings → Privacy & Security → Accessibility → enable myCoder",
                "nodes": []
            ]
        }
        guard let window = keyWindow() else {
            return ["trusted": true, "error": "No key window", "nodes": []]
        }
        var entries: [Entry] = []
        collect(window, path: "0", depth: 0, maxDepth: maxDepth, limit: limit, into: &entries)
        return [
            "trusted": true,
            "app": NSRunningApplication.current.localizedName ?? "myCoder",
            "window": stringAttribute(window, kAXTitleAttribute) ?? "",
            "count": entries.count,
            "nodes": entries.map { entry in
                var row: [String: Any] = [
                    "path": entry.path,
                    "index": entry.index,
                    "role": entry.role,
                    "title": entry.title,
                    "description": entry.description,
                    "identifier": entry.identifier,
                    "enabled": entry.enabled,
                    "children": entry.children
                ]
                if !entry.value.isEmpty { row["value"] = entry.value }
                return row
            }
        ]
    }

    static func click(params: [String: Any]) throws -> [String: Any] {
        activate()
        guard AXIsProcessTrusted() else {
            throw AppActionError.failed("Accessibility permission is not granted to myCoder")
        }
        guard let window = keyWindow() else {
            throw AppActionError.failed("No key window")
        }
        var entries: [Entry] = []
        collect(window, path: "0", depth: 0, maxDepth: 12, limit: 2000, into: &entries)
        guard let target = match(params: params, entries: entries, window: window) else {
            throw AppActionError.notFound("accessibility element")
        }
        let result = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
        guard result == .success else {
            throw AppActionError.failed("AXPress failed (\(result.rawValue)) for \(target.role) \(target.title)")
        }
        return [
            "status": "pressed",
            "path": target.path,
            "role": target.role,
            "title": target.title,
            "identifier": target.identifier
        ]
    }

    static func setValue(params: [String: Any]) throws -> [String: Any] {
        activate()
        guard AXIsProcessTrusted() else {
            throw AppActionError.failed("Accessibility permission is not granted to myCoder")
        }
        guard let value = params["value"] as? String else {
            throw AppActionError.missingParameter("value")
        }
        guard let window = keyWindow() else {
            throw AppActionError.failed("No key window")
        }
        var entries: [Entry] = []
        collect(window, path: "0", depth: 0, maxDepth: 12, limit: 2000, into: &entries)
        guard let target = match(params: params, entries: entries, window: window) else {
            throw AppActionError.notFound("accessibility element")
        }
        let result = AXUIElementSetAttributeValue(
            target.element,
            kAXValueAttribute as CFString,
            value as CFTypeRef
        )
        guard result == .success else {
            throw AppActionError.failed("AXValue set failed (\(result.rawValue)) for \(target.role) \(target.title)")
        }
        return [
            "status": "set",
            "path": target.path,
            "role": target.role,
            "title": target.title,
            "value": value
        ]
    }

    // MARK: - Tree

    private static func keyWindow() -> AXUIElement? {
        let app = AXUIElementCreateApplication(getpid())
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let window = windows.first else { return nil }
        return window
    }

    private static func collect(_ element: AXUIElement,
                                path: String,
                                depth: Int,
                                maxDepth: Int,
                                limit: Int,
                                into entries: inout [Entry]) {
        guard entries.count < limit else { return }
        let role = stringAttribute(element, kAXRoleAttribute) ?? ""
        let title = stringAttribute(element, kAXTitleAttribute) ?? ""
        let description = stringAttribute(element, kAXDescriptionAttribute) ?? ""
        let help = stringAttribute(element, kAXHelpAttribute) ?? ""
        let identifier = stringAttribute(element, kAXIdentifierAttribute) ?? ""
        let value = stringAttribute(element, kAXValueAttribute) ?? ""
        let enabled = boolAttribute(element, kAXEnabledAttribute) ?? true
        let children = childElements(element)
        entries.append(Entry(
            element: element,
            path: path,
            index: entries.count,
            role: role,
            title: title,
            description: description.isEmpty ? help : description,
            identifier: identifier,
            value: value,
            enabled: enabled,
            children: children.count
        ))
        guard depth < maxDepth else { return }
        for (offset, child) in children.enumerated() {
            guard entries.count < limit else { return }
            collect(child,
                    path: "\(path).\(offset)",
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    limit: limit,
                    into: &entries)
        }
    }

    private static func match(params: [String: Any],
                              entries: [Entry],
                              window: AXUIElement) -> Entry? {
        if let rawPath = params["path"] as? String, !rawPath.isEmpty {
            return resolve(path: rawPath, window: window)
        }
        if let index = params["index"] as? Int, entries.indices.contains(index) {
            return entries[index]
        }
        if let index = (params["index"] as? String).flatMap(Int.init), entries.indices.contains(index) {
            return entries[index]
        }
        let identifier = (params["identifier"] as? String) ?? ""
        let title = (params["title"] as? String) ?? ""
        let role = params["role"] as? String

        func roleMatches(_ entry: Entry) -> Bool {
            guard let role, !role.isEmpty else { return true }
            return entry.role == role
        }
        if !identifier.isEmpty {
            if let hit = entries.first(where: { roleMatches($0) && $0.identifier == identifier }) {
                return hit
            }
            if let hit = entries.first(where: { roleMatches($0) && $0.identifier.contains(identifier) }) {
                return hit
            }
        }
        if !title.isEmpty {
            if let hit = entries.first(where: { roleMatches($0) && ($0.title == title || $0.description == title) }) {
                return hit
            }
            if let hit = entries.first(where: {
                roleMatches($0) && ($0.title.localizedCaseInsensitiveContains(title)
                                    || $0.description.localizedCaseInsensitiveContains(title))
            }) {
                return hit
            }
        }
        return nil
    }

    private static func resolve(path: String, window: AXUIElement) -> Entry? {
        let components = path.split(separator: ".").compactMap { Int($0) }
        guard !components.isEmpty else { return nil }
        var current = window
        for (offset, index) in components.enumerated() {
            if offset == 0 {
                guard index == 0 else { return nil }
                continue
            }
            let children = childElements(current)
            guard children.indices.contains(index) else { return nil }
            current = children[index]
        }
        return Entry(
            element: current,
            path: path,
            index: -1,
            role: stringAttribute(current, kAXRoleAttribute) ?? "",
            title: stringAttribute(current, kAXTitleAttribute) ?? "",
            description: stringAttribute(current, kAXDescriptionAttribute) ?? "",
            identifier: stringAttribute(current, kAXIdentifierAttribute) ?? "",
            value: stringAttribute(current, kAXValueAttribute) ?? "",
            enabled: boolAttribute(current, kAXEnabledAttribute) ?? true,
            children: childElements(current).count
        )
    }

    private static func childElements(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }
}
