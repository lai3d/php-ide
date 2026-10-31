import Foundation

/// How to run/debug PHP: a CLI script, or the built-in web server — with arguments and environment.
public struct RunConfiguration: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case script, server
    }

    public var id = UUID()
    public var name: String
    public var kind: Kind
    /// Script path relative to the project root, e.g. "index.php" or "bin/console".
    /// For a web server: the optional router script ("" for none).
    public var script: String
    /// Program arguments, shell-style (quotes group words). Unused by the web server.
    public var arguments: String
    /// Extra environment, one `KEY=value` per line.
    public var environment: String
    /// Web server: document root relative to the project root ("public", "." for the root).
    public var documentRoot: String
    /// Web server: port on 127.0.0.1.
    public var port: Int

    public init(name: String, script: String, arguments: String = "", environment: String = "") {
        self.name = name
        self.kind = .script
        self.script = script
        self.arguments = arguments
        self.environment = environment
        self.documentRoot = "public"
        self.port = 8000
    }

    /// A built-in web server serving `documentRoot` (optionally through a router script).
    public static func server(name: String, documentRoot: String, port: Int = 8000, router: String = "") -> RunConfiguration {
        var config = RunConfiguration(name: name, script: router)
        config.kind = .server
        config.documentRoot = documentRoot
        config.port = port
        return config
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .script
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        arguments = try c.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        environment = try c.decodeIfPresent(String.self, forKey: .environment) ?? ""
        documentRoot = try c.decodeIfPresent(String.self, forKey: .documentRoot) ?? "public"
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 8000
    }

    /// Arguments after `php` (and after any Xdebug flags) for this configuration.
    public var phpArguments: [String] {
        switch kind {
        case .script:
            return [script] + argumentList
        case .server:
            let root = documentRoot.isEmpty ? "." : documentRoot
            return ["-S", "127.0.0.1:\(port)", "-t", root] + (script.isEmpty ? [] : [script])
        }
    }

    /// Where the web server answers (nil for scripts).
    public var url: URL? {
        kind == .server ? URL(string: "http://127.0.0.1:\(port)/") : nil
    }

    public var argumentList: [String] { ShellWords.split(arguments) }

    public var environmentVariables: [String: String] {
        var result: [String: String] = [:]
        for line in environment.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            result[String(trimmed[..<eq])] = String(trimmed[trimmed.index(after: eq)...])
        }
        return result
    }
}

public enum ShellWords {
    /// Splits like a shell: whitespace separates words; '…' and "…" group; backslash escapes.
    public static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for c in line {
            if escaped {
                current.append(c)
                escaped = false
            } else if c == "\\" && quote != "'" {
                escaped = true
                inWord = true
            } else if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
            } else if c == "\"" || c == "'" {
                quote = c
                inWord = true
            } else if c.isWhitespace {
                if inWord { words.append(current); current = ""; inWord = false }
            } else {
                current.append(c)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}

public enum PHPScripts {
    /// Runnable entry points under `root` (relative paths): PHP files in the root, `public/index.php`,
    /// everything in `bin/`, and root files with a `#!…php` shebang (e.g. Laravel's `artisan`).
    public static func entryPoints(under root: URL) -> [String] {
        let rootPath = root.canonicalFileURL.path
        var found: [String] = []
        for path in ProjectSearch.files(under: root) {
            guard path.hasPrefix(rootPath + "/") else { continue }
            let relative = String(path.dropFirst(rootPath.count + 1))
            let parts = relative.split(separator: "/")
            let isPHP = relative.hasSuffix(".php")
            if parts.count == 1, isPHP || hasPHPShebang(path) {
                found.append(relative)
            } else if relative == "public/index.php" || (parts.count == 2 && parts[0] == "bin" && (isPHP || hasPHPShebang(path))) {
                found.append(relative)
            }
        }
        let preferred = ["index.php", "main.php", "public/index.php", "artisan", "bin/console"]
        return found.sorted { a, b in
            let (ia, ib) = (preferred.firstIndex(of: a) ?? .max, preferred.firstIndex(of: b) ?? .max)
            if ia != ib { return ia < ib }
            let (da, db) = (a.split(separator: "/").count, b.split(separator: "/").count)
            return da != db ? da < db : a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    static func hasPHPShebang(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 64)) ?? Data(), as: UTF8.self)
        return head.hasPrefix("#!") && head.prefix(while: { $0 != "\n" }).contains("php")
    }
}
