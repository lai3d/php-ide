import Foundation

/// The vscode-php-debug DAP adapter (MIT), downloaded on first use and run with `node`.
public enum PHPDebugAdapter {
    public static let version = "1.40.2"

    public static var downloadURL: URL {
        URL(string: "https://github.com/xdebug/vscode-php-debug/releases/download/v\(version)/php-debug-\(version).vsix")!
    }

    /// `~/Library/Application Support/PHPIDE/php-debug`.
    public static var baseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PHPIDE/php-debug")
    }

    /// `phpDebug.js` of an installed copy: the pinned version, else the newest one present.
    public static func installedScript(in base: URL = baseDirectory) -> URL? {
        let pinned = script(in: base.appendingPathComponent(version))
        if FileManager.default.fileExists(atPath: pinned.path) { return pinned }
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { script(in: base.appendingPathComponent($0)) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func script(in versionDirectory: URL) -> URL {
        versionDirectory.appendingPathComponent("extension/out/phpDebug.js")
    }

    public enum InstallError: Error, LocalizedError {
        case download(String), unpack(String)
        public var errorDescription: String? {
            switch self {
            case .download(let m): "couldn't download vscode-php-debug: \(m)"
            case .unpack(let m): "couldn't unpack vscode-php-debug: \(m)"
            }
        }
    }

    /// Downloads and unpacks the pinned version (a VSIX is a zip), returning `phpDebug.js`.
    public static func install(into base: URL = baseDirectory, from source: URL = downloadURL) async throws -> URL {
        let fm = FileManager.default
        let archive: URL
        if source.isFileURL {
            archive = source
        } else {
            let (downloaded, response) = try await URLSession.shared.download(from: source)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw InstallError.download("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            archive = downloaded
        }
        let staging = base.appendingPathComponent(".staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let unzip = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-q", "-o", archive.path, "-d", staging.path])
        guard unzip.status == 0, fm.fileExists(atPath: script(in: staging).path) else {
            throw InstallError.unpack(unzip.output.isEmpty ? "phpDebug.js missing" : unzip.output)
        }
        let target = base.appendingPathComponent(version)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: staging, to: target)
        return script(in: target)
    }

    /// `launch` arguments for running `program` under the debugger. Port 0 lets the adapter pick a free
    /// port and pass it to php; Xdebug is loaded for this run only (see `XdebugStatus.runtimeArguments`).
    /// With `program` nil, `phpArguments` (e.g. `-S 127.0.0.1:8000 -t public`) say what php runs.
    public static func launchArguments(program: String?, cwd: String, php: String, xdebug: XdebugStatus,
                                       arguments: [String] = [], environment: [String: String] = [:],
                                       phpArguments: [String] = []) -> JSONValue {
        var config: [String: JSONValue] = [
            "request": "launch",
            "cwd": .string(cwd),
            "port": 0,
            "runtimeExecutable": .string(php),
            // The adapter substitutes `${port}` with the port it actually listens on; php must be told.
            "runtimeArgs": .array((xdebug.runtimeArguments + ["-dxdebug.client_port=${port}"] + phpArguments).map(JSONValue.string)),
            "args": .array(arguments.map(JSONValue.string)),
            "env": .object(environment.mapValues(JSONValue.string)),
            "stopOnEntry": false,
        ]
        if let program { config["program"] = .string(program) }
        return .object(config)
    }

    /// `launch` arguments without a program: wait for Xdebug to connect (web requests, CLI runs elsewhere).
    public static func listenArguments(port: Int = 9003) -> JSONValue {
        ["request": "launch", "port": .int(port), "stopOnEntry": false]
    }

    /// The `evaluate` context for a watch expression. vscode-php-debug answers `watch` with Xdebug's
    /// property_get first, which reads `$a['x'] * 10` as just `$a['x']`; anything beyond a plain
    /// variable path therefore goes through `repl` (a real eval).
    public static func evaluateContext(forWatch expression: String) -> String {
        let path = #"^\$[A-Za-z_]\w*(?:->[A-Za-z_]\w*|\[(?:'[^']*'|"[^"]*"|\d+)\])*$"#
        return expression.trimmingCharacters(in: .whitespaces).range(of: path, options: .regularExpression) != nil ? "watch" : "repl"
    }
}
