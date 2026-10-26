import Foundation

/// Canonical UserDefaults identity for myCoder: `com.mycoder.*`.
enum MyCoderDefaults {
    static func key(_ suffix: String) -> String {
        MyCoderPaths.bundleKey(suffix)
    }

    static func string(_ suffix: String, in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key(suffix))
    }

    static func set(_ value: String, _ suffix: String, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: key(suffix))
    }
}
