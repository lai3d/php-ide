import Foundation

/// How to launch a PHP language server.
public struct LanguageServerCommand: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case intelephense, phpactor
    }

    public let kind: Kind
    public let executable: URL
    public let arguments: [String]

    public var name: String { kind.rawValue }
}

/// Locates and configures the PHP language server: Intelephense (default) or Phpactor.
public enum PHPLanguageServer {
    /// UserDefaults key for the preferred server (`intelephense` / `phpactor`); unset = Intelephense, else Phpactor.
    public static let preferenceKey = "languageServer"
    /// UserDefaults key for an Intelephense premium licence key (unlocks rename, code actions, folding, …).
    public static let licenceKeyDefaultsKey = "intelephense.licenceKey"

    public static let installHint = "npm install -g intelephense  (or brew install phpactor)"

    /// File extensions handed to the language server.
    public static let fileExtensions: Set<String> = ["php", "phtml", "php8", "inc"]

    public static func isPHPFile(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }

    /// The preferred server if installed, else whichever one is.
    public static func locate(
        preferred: LanguageServerCommand.Kind? = nil,
        find: (String) -> URL? = { ToolLocator.find($0) }
    ) -> LanguageServerCommand? {
        let preferred = preferred
            ?? UserDefaults.standard.string(forKey: preferenceKey).flatMap(LanguageServerCommand.Kind.init(rawValue:))
            ?? .intelephense
        let order: [LanguageServerCommand.Kind] = preferred == .intelephense ? [.intelephense, .phpactor] : [.phpactor, .intelephense]
        for kind in order {
            guard let executable = find(kind.rawValue) else { continue }
            switch kind {
            case .intelephense: return LanguageServerCommand(kind: kind, executable: executable, arguments: ["--stdio"])
            case .phpactor: return LanguageServerCommand(kind: kind, executable: executable, arguments: ["language-server"])
            }
        }
        return nil
    }

    /// `initializationOptions` for `initialize`.
    public static func initializationOptions(for kind: LanguageServerCommand.Kind, licenceKey: String? = nil) -> JSONValue {
        switch kind {
        case .intelephense:
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PHPIDE/intelephense")
            var options: [String: JSONValue] = [
                "storagePath": .string(cache.appendingPathComponent("workspace").path),
                "globalStoragePath": .string(cache.appendingPathComponent("global").path),
                "clearCache": false,
            ]
            if let key = licenceKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                options["licenceKey"] = .string(key)
            }
            return .object(options)
        case .phpactor:
            return [:]
        }
    }

    /// Whether a changed file on disk is worth a `workspace/didChangeWatchedFiles`.
    public static func isWatched(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        return isPHPFile(url) || url.lastPathComponent == "composer.json" || url.lastPathComponent == "composer.lock"
    }
}
