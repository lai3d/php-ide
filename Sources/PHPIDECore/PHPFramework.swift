import Foundation

/// A framework console the IDE can drive: Laravel's `artisan` or Symfony's `bin/console`
/// (both Symfony Console applications).
public enum PHPFramework: String, Sendable, CaseIterable {
    case laravel, symfony

    public var displayName: String { self == .laravel ? "Laravel" : "Symfony" }
    /// The console script, relative to the project root.
    public var console: String { self == .laravel ? "artisan" : "bin/console" }
    public var consoleName: String { self == .laravel ? "Artisan" : "Console" }

    public static func detect(in root: URL) -> PHPFramework? {
        allCases.first { FileManager.default.fileExists(atPath: root.appendingPathComponent($0.console).path) }
    }

    public var listArguments: [String] { [console, "list", "--format=json"] }
    public var routeArguments: [String] {
        self == .laravel ? [console, "route:list", "--json"] : [console, "debug:router", "--format=json"]
    }
}

public struct ConsoleCommand: Sendable, Hashable, Identifiable {
    public let name: String
    public let description: String
    public var id: String { name }
}

public struct FrameworkRoute: Sendable, Hashable, Identifiable {
    public let methods: String
    public let path: String
    public let name: String?
    /// `App\Http\Controllers\UserController@show`, `App\Controller\HomeController::index`, `Closure`.
    public let action: String?
    public var id: String { methods + " " + path + " " + (name ?? "") }
}

extension PHPFramework {
    /// The first JSON value (object or array) in `output`, which may be preceded by warnings.
    static func json(in output: String) -> JSONValue? {
        guard let start = output.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: Data(output[start...].utf8))
    }

    /// `list --format=json` → visible commands, sorted by name.
    public static func parseCommands(_ output: String) -> [ConsoleCommand] {
        (json(in: output)?["commands"]?.arrayValue ?? []).compactMap { command in
            guard let name = command["name"]?.stringValue, command["hidden"]?.boolValue != true else { return nil }
            return ConsoleCommand(name: name, description: command["description"]?.stringValue ?? "")
        }
        .sorted { $0.name < $1.name }
    }

    /// Laravel `route:list --json` (an array) or Symfony `debug:router --format=json` (an object by route name).
    public func parseRoutes(_ output: String) -> [FrameworkRoute] {
        guard let value = Self.json(in: output) else { return [] }
        switch self {
        case .laravel:
            return (value.arrayValue ?? []).compactMap { route in
                guard let uri = route["uri"]?.stringValue else { return nil }
                return FrameworkRoute(methods: route["method"]?.stringValue ?? "ANY",
                                      path: uri.hasPrefix("/") ? uri : "/" + uri,
                                      name: route["name"]?.stringValue, action: route["action"]?.stringValue)
            }
        case .symfony:
            return (value.objectValue ?? [:]).compactMap { name, route in
                guard let path = route["path"]?.stringValue else { return nil }
                return FrameworkRoute(methods: route["method"]?.stringValue ?? "ANY", path: path, name: name,
                                      action: route["defaults"]?["_controller"]?.stringValue)
            }
            .sorted { ($0.path, $0.methods) < ($1.path, $1.methods) }
        }
    }

    /// `Class@method` / `Class::method` / an invokable `Class` → its parts (nil for closures).
    public static func controller(of action: String) -> (className: String, method: String?)? {
        let trimmed = action.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "Closure", !trimmed.hasPrefix("Closure") else { return nil }
        for separator in ["@", "::"] {
            if let range = trimmed.range(of: separator) {
                return (String(trimmed[..<range.lowerBound]), String(trimmed[range.upperBound...]))
            }
        }
        return trimmed.contains("\\") ? (trimmed, nil) : nil
    }
}

extension Composer {
    /// The file declaring class `fqcn`: through composer.json's PSR-4 map, else by file name in the project.
    public static func file(forClass fqcn: String, in root: URL) -> URL? {
        let className = fqcn.hasPrefix("\\") ? String(fqcn.dropFirst()) : fqcn
        if let data = try? Data(contentsOf: root.appendingPathComponent("composer.json")),
           let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            for section in ["autoload", "autoload-dev"] {
                for (prefix, dirs) in json[section]?["psr-4"]?.objectValue ?? [:] where className.hasPrefix(prefix) {
                    let relative = className.dropFirst(prefix.count).replacingOccurrences(of: "\\", with: "/") + ".php"
                    let candidates = dirs.stringValue.map { [$0] } ?? (dirs.arrayValue ?? []).compactMap(\.stringValue)
                    for dir in candidates {
                        let url = root.appendingPathComponent(dir).appendingPathComponent(relative)
                        if FileManager.default.fileExists(atPath: url.path) { return url }
                    }
                }
            }
        }
        let short = "/" + (className.split(separator: "\\").last.map(String.init) ?? className) + ".php"
        return ProjectSearch.files(under: root).first { $0.hasSuffix(short) }.map(URL.init(fileURLWithPath:))
    }
}
