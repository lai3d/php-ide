import Foundation

/// Project formatters (Laravel Pint, PHP-CS-Fixer, PHP_CodeSniffer's phpcbf), found in `vendor/bin`.
/// They format files in place, so text is formatted through a temporary file next to the original
/// (same folder → same config lookup and path rules).
public enum PHPFormatter: String, Sendable, CaseIterable {
    case pint, phpCsFixer = "php-cs-fixer", phpcbf

    public var displayName: String {
        switch self {
        case .pint: "Laravel Pint"
        case .phpCsFixer: "PHP-CS-Fixer"
        case .phpcbf: "phpcbf"
        }
    }

    /// The project's formatter: Pint, then PHP-CS-Fixer, then phpcbf (first present in vendor/bin).
    public static func locate(in root: URL) -> (PHPFormatter, URL)? {
        for formatter in allCases {
            let url = root.appendingPathComponent("vendor/bin/\(formatter.rawValue)")
            if FileManager.default.isExecutableFile(atPath: url.path) { return (formatter, url) }
        }
        return nil
    }

    /// Arguments to format `file` in place, using the project's config when there is one.
    public func arguments(file: String, root: URL) -> [String] {
        let fm = FileManager.default
        func config(_ names: [String]) -> String? {
            names.map { root.appendingPathComponent($0).path }.first { fm.fileExists(atPath: $0) }
        }
        switch self {
        case .pint:
            return [file] + (config(["pint.json"]).map { ["--config=\($0)"] } ?? []) + ["--no-interaction"]
        case .phpCsFixer:
            return ["fix", file, "--path-mode=override", "--no-interaction", "--quiet"]
                + (config([".php-cs-fixer.php", ".php-cs-fixer.dist.php"]).map { ["--config=\($0)"] } ?? [])
        case .phpcbf:
            return [file, "-q"] + (config(["phpcs.xml", "phpcs.xml.dist", ".phpcs.xml", ".phpcs.xml.dist"]).map { ["--standard=\($0)"] } ?? ["--standard=PSR12"])
        }
    }

    /// Formats `text` (the contents of `original`) and returns the result, or nil if the tool failed.
    public func format(_ text: String, original: URL, executable: URL, root: URL) async -> String? {
        let temp = original.deletingLastPathComponent()
            .appendingPathComponent(".phpide-format-\(UUID().uuidString.prefix(8)).\(original.pathExtension.isEmpty ? "php" : original.pathExtension)")
        guard (try? text.write(to: temp, atomically: false, encoding: .utf8)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: temp) }
        let result = await ProcessRunner.run(executable, arguments(file: temp.path, root: root), in: root)
        // phpcbf exits 1 when it fixed something; the others 0 (Pint: 1 only with --test).
        let ok = self == .phpcbf ? result.status <= 1 : result.status == 0
        guard ok, let formatted = try? String(contentsOf: temp, encoding: .utf8) else { return nil }
        return formatted
    }
}
