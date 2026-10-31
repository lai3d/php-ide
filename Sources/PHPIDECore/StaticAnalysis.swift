import Foundation

/// PHPStan / Psalm: finding them, how to run them, and parsing their JSON reports.
public enum StaticAnalyzer: String, Sendable, CaseIterable {
    case phpstan, psalm

    public var source: String { rawValue }
    public var displayName: String { self == .phpstan ? "PHPStan" : "Psalm" }

    /// The project's `vendor/bin` copy, else a global install (Composer global bin, Homebrew, PATH).
    public func locate(in root: URL, find: (String) -> URL? = { ToolLocator.find($0) }) -> URL? {
        let local = root.appendingPathComponent("vendor/bin/\(rawValue)")
        if FileManager.default.isExecutableFile(atPath: local.path) { return local }
        return find(rawValue)
    }

    /// The first analyzer available for `root`: one with a config file wins, PHPStan before Psalm.
    public static func preferred(in root: URL, find: (String) -> URL? = { ToolLocator.find($0) }) -> (StaticAnalyzer, URL)? {
        let available = allCases.compactMap { analyzer in analyzer.locate(in: root, find: find).map { (analyzer, $0) } }
        return available.first { $0.0.hasConfig(in: root) } ?? available.first
    }

    public func hasConfig(in root: URL) -> Bool {
        let names = self == .phpstan
            ? ["phpstan.neon", "phpstan.neon.dist", "phpstan.dist.neon"]
            : ["psalm.xml", "psalm.xml.dist"]
        return names.contains { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
    }

    public func arguments(in root: URL) -> [String] {
        switch self {
        case .phpstan:
            var args = ["analyse", "--error-format=json", "--no-progress", "--no-interaction"]
            if !hasConfig(in: root) {
                // No config: analyse the usual source folders (PHPStan needs explicit paths then).
                let dirs = ["src", "app", "lib"].filter {
                    var isDir: ObjCBool = false
                    return FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path, isDirectory: &isDir) && isDir.boolValue
                }
                args += dirs.isEmpty ? ["."] : dirs
            }
            return args
        case .psalm:
            return ["--output-format=json", "--no-progress", "--no-cache"]
        }
    }

    /// Problems by absolute path (relative paths are resolved against `root`).
    public func parse(_ output: String, root: URL) -> [String: [Diagnostic]]? {
        switch self {
        case .phpstan: Self.parsePHPStan(output, root: root)
        case .psalm: Self.parsePsalm(output, root: root)
        }
    }

    // MARK: - Report parsing

    /// The JSON value in `output`, which may be surrounded by other text (warnings, banners).
    static func jsonValue(in output: String, opening: Character) -> JSONValue? {
        var search = output.startIndex
        while let start = output[search...].firstIndex(of: opening) {
            if let data = String(output[start...]).data(using: .utf8),
               let value = try? JSONDecoder().decode(JSONValue.self, from: Self.trimmedToBalanced(data)) {
                return value
            }
            search = output.index(after: start)
        }
        return nil
    }

    /// Cuts `data` after the bracket that closes its first one (ignoring brackets inside strings).
    private static func trimmedToBalanced(_ data: Data) -> Data {
        var depth = 0, inString = false, escaped = false
        for (i, byte) in data.enumerated() {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22: inString = true
            case 0x7B, 0x5B: depth += 1
            case 0x7D, 0x5D:
                depth -= 1
                if depth == 0 { return data.prefix(i + 1) }
            default: break
            }
        }
        return data
    }

    static func parsePHPStan(_ output: String, root: URL) -> [String: [Diagnostic]]? {
        guard let report = jsonValue(in: output, opening: "{"), let files = report["files"]?.objectValue else { return nil }
        var result: [String: [Diagnostic]] = [:]
        for (file, entry) in files {
            // "path (in context of class X)" for trait files.
            let path = absolute(String(file.split(separator: " (in context of").first ?? Substring(file)), root: root)
            for message in entry["messages"]?.arrayValue ?? [] {
                guard let text = message["message"]?.stringValue else { continue }
                let line = max((message["line"]?.intValue ?? 1) - 1, 0)
                let position = TextPosition(line: line, character: 0)
                var full = text
                if let identifier = message["identifier"]?.stringValue { full += " [\(identifier)]" }
                result[path, default: []].append(Diagnostic(start: position, end: position, severity: .error,
                                                            message: full, source: StaticAnalyzer.phpstan.source))
            }
        }
        return result
    }

    static func parsePsalm(_ output: String, root: URL) -> [String: [Diagnostic]]? {
        guard let issues = jsonValue(in: output, opening: "[")?.arrayValue else { return nil }
        var result: [String: [Diagnostic]] = [:]
        for issue in issues {
            guard let message = issue["message"]?.stringValue,
                  let file = issue["file_path"]?.stringValue ?? issue["file_name"]?.stringValue else { continue }
            let startLine = max((issue["line_from"]?.intValue ?? 1) - 1, 0)
            let endLine = max((issue["line_to"]?.intValue ?? startLine + 1) - 1, startLine)
            let start = TextPosition(line: startLine, character: max((issue["column_from"]?.intValue ?? 1) - 1, 0))
            let end = TextPosition(line: endLine, character: max((issue["column_to"]?.intValue ?? 1) - 1, 0))
            let severity: Diagnostic.Severity = issue["severity"]?.stringValue == "error" ? .error : .warning
            var full = message
            if let type = issue["type"]?.stringValue { full += " [\(type)]" }
            result[absolute(file, root: root), default: []].append(
                Diagnostic(start: start, end: end, severity: severity, message: full, source: StaticAnalyzer.psalm.source))
        }
        return result
    }

    private static func absolute(_ path: String, root: URL) -> String {
        path.hasPrefix("/") ? path : root.appendingPathComponent(path).path
    }
}
