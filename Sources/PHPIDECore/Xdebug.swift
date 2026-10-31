import Foundation

/// Whether (and how) Xdebug is available to a PHP binary.
public enum XdebugStatus: Sendable, Equatable {
    /// Loaded by php.ini already.
    case loaded
    /// `xdebug.so` sits in the extension dir but isn't enabled: PHPIDE loads it per debug run only.
    case installed(path: String)
    case missing

    /// `php` flags that turn step debugging on for one run.
    public var runtimeArguments: [String] {
        var args: [String] = []
        if case .installed(let path) = self { args.append("-dzend_extension=\(path)") }
        guard self != .missing else { return [] }
        args += ["-dxdebug.mode=debug", "-dxdebug.start_with_request=yes"]
        return args
    }

    public var isAvailable: Bool { self != .missing }
}

public enum Xdebug {
    public static let installHint = "pecl install xdebug"

    /// Asks `php` whether Xdebug is loaded, else looks for `xdebug.so` in its extension dir.
    public static func status(php: URL) async -> XdebugStatus {
        let script = #"echo "\n", extension_loaded('xdebug') ? 'loaded' : ini_get('extension_dir'), "\n";"#
        return status(extensionDirOutput: await ProcessRunner.run(php, ["-r", script]).output)
    }

    static func status(extensionDirOutput output: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> XdebugStatus {
        let line = output.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if line == "loaded" { return .loaded }
        guard line.hasPrefix("/") else { return .missing }
        let path = (line as NSString).appendingPathComponent("xdebug.so")
        return fileExists(path) ? .installed(path: path) : .missing
    }
}
