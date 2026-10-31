import Foundation

/// Bits of a project's composer.json the IDE uses.
public enum Composer {
    /// Script names from `scripts` (custom commands first, then event hooks like `post-install-cmd`).
    public static func scripts(in root: URL) -> [String] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("composer.json")),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let scripts = json["scripts"]?.objectValue
        else { return [] }
        let isHook = { (name: String) in name.hasPrefix("pre-") || name.hasPrefix("post-") }
        return scripts.keys.sorted { a, b in
            isHook(a) != isHook(b) ? !isHook(a) : a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}

/// A direct dependency from composer.json, with what composer.lock / `composer outdated` say about it.
public struct ComposerPackage: Sendable, Hashable, Identifiable {
    public let name: String
    public let constraint: String
    public let isDev: Bool
    /// From composer.lock (nil when not installed / no lock file).
    public var installed: String?
    /// From `composer outdated` (nil until checked, or when up to date).
    public var latest: String?
    /// `semver-safe-update` / `update-possible` / `up-to-date`.
    public var latestStatus: String?

    public var id: String { name }
    /// Platform requirements (`php`, `ext-json`) can't be updated or removed like packages.
    public var isPlatform: Bool { name == "php" || name.hasPrefix("ext-") || name.hasPrefix("lib-") || !name.contains("/") }
}

extension Composer {
    /// `require` then `require-dev` from composer.json, annotated with composer.lock's versions.
    public static func packages(in root: URL) -> [ComposerPackage] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("composer.json")),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        let locked = lockedVersions(in: root)
        func list(_ key: String, dev: Bool) -> [ComposerPackage] {
            (json[key]?.objectValue ?? [:]).map { name, constraint in
                ComposerPackage(name: name, constraint: constraint.stringValue ?? "", isDev: dev,
                                installed: locked[name.lowercased()])
            }
            .sorted { ($0.isPlatform ? 0 : 1, $0.name) < ($1.isPlatform ? 0 : 1, $1.name) }
        }
        return list("require", dev: false) + list("require-dev", dev: true)
    }

    /// Package name (lowercased) → version from composer.lock.
    public static func lockedVersions(in root: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("composer.lock")),
              let lock = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        var versions: [String: String] = [:]
        for key in ["packages", "packages-dev"] {
            for package in lock[key]?.arrayValue ?? [] {
                if let name = package["name"]?.stringValue, let version = package["version"]?.stringValue {
                    versions[name.lowercased()] = version
                }
            }
        }
        return versions
    }

    /// `composer outdated --direct --format=json`: name (lowercased) → (latest, status).
    public static func parseOutdated(_ output: String) -> [String: (latest: String, status: String)] {
        guard let start = output.firstIndex(of: "{"),
              let json = try? JSONDecoder().decode(JSONValue.self, from: Data(output[start...].utf8)) else { return [:] }
        var result: [String: (String, String)] = [:]
        for entry in json["installed"]?.arrayValue ?? [] {
            guard let name = entry["name"]?.stringValue, let latest = entry["latest"]?.stringValue else { continue }
            result[name.lowercased()] = (latest, entry["latest-status"]?.stringValue ?? "")
        }
        return result
    }

    /// Whether `name` looks like a Packagist package (`vendor/name`, lowercase).
    public static func isValidPackageName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9]([_.-]?[a-z0-9]+)*/[a-z0-9](([_.]|-{1,2})?[a-z0-9]+)*$"#, options: .regularExpression) != nil
    }
}
