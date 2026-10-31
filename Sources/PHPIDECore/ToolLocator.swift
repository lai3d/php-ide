import Foundation

/// Finds PHP tooling (php, composer, node, intelephense, phpactor). GUI apps launched from Finder
/// get a minimal PATH, so we also look in the usual Homebrew, Composer and npm install locations.
public enum ToolLocator {
    public static func searchDirectories(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        if let composerHome = environment["COMPOSER_HOME"] { dirs.append("\(composerHome)/vendor/bin") }
        if let npmPrefix = environment["NPM_CONFIG_PREFIX"] { dirs.append("\(npmPrefix)/bin") }
        dirs += ["/opt/homebrew/bin", "/usr/local/bin",
                 "\(home)/.composer/vendor/bin", "\(home)/.config/composer/vendor/bin",
                 "\(home)/.npm-global/bin", "\(home)/.volta/bin", "\(home)/.local/bin",
                 "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// UserDefaults key for a user-chosen tool path (set in Settings).
    public static func overrideKey(for name: String) -> String { "toolPath.\(name)" }

    public static func find(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let custom = UserDefaults.standard.string(forKey: overrideKey(for: name))?
            .trimmingCharacters(in: .whitespaces), !custom.isEmpty {
            let path = (custom as NSString).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        for dir in searchDirectories(environment: environment) {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// The current environment with PATH widened to every search directory,
    /// so child processes (intelephense → node, composer → php) can find each other.
    public static func environment(
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env["PATH"] = searchDirectories(environment: base).joined(separator: ":")
        return env
    }
}

public extension URL {
    /// The canonical file URL as the OS (and the language server) sees it: symlinks resolved and
    /// `/tmp` → `/private/tmp`. Unlike `resolvingSymlinksInPath()`, keeps `/private`.
    var canonicalFileURL: URL {
        guard isFileURL, let resolved = realpath(path, nil) else { return standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: hasDirectoryPath)
    }
}
