import Foundation

/// The project's database connection, from `.env` (Laravel `DB_*` / `DB_URL`, Symfony `DATABASE_URL`).
public struct DatabaseSettings: Sendable, Equatable {
    /// Matches DBIDE's `SQLDialect` raw values: sqlite, postgres, mysql, sqlserver, …
    public var dialect: String
    public var host: String = ""
    public var port: Int?
    public var user: String = ""
    public var password: String = ""
    public var database: String = ""
    /// SQLite database file (absolute).
    public var filePath: String = ""
    /// Which variable(s) it came from, for display.
    public var source: String

    public static let defaultPorts = ["mysql": 3306, "postgres": 5432, "sqlserver": 1433]

    /// `scheme://user:password@host:port/database` (password omitted unless asked for), or `sqlite:///path`.
    public func url(includingPassword: Bool = false) -> String {
        if dialect == "sqlite" { return "sqlite://" + filePath }
        let scheme = dialect == "postgres" ? "postgresql" : dialect
        var auth = user.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? user
        if includingPassword, !password.isEmpty {
            auth += ":" + (password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password)
        }
        let portPart = port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(auth.isEmpty ? "" : auth + "@")\(host)\(portPart)/\(database)"
    }

    /// `dbide://connect?url=…&name=…`: DBIDE opens the matching saved data source, or a filled-in
    /// New Data Source sheet (password included, so it can connect without asking).
    public func dbideLink(name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "dbide"
        components.host = "connect"
        components.queryItems = [URLQueryItem(name: "url", value: url(includingPassword: true)),
                                 URLQueryItem(name: "name", value: name)]
        // `+` would read as a space; `&`/`=` are already escaped inside values.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    /// Reads `.env` then `.env.local` (later files override) in `root`.
    public static func fromEnvironmentFiles(in root: URL) -> DatabaseSettings? {
        var env: [String: String] = [:]
        for name in [".env", ".env.local"] {
            guard let text = try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) else { continue }
            env.merge(parseDotEnv(text, inheriting: env)) { $1 }
        }
        return from(env, root: root)
    }

    static func from(_ env: [String: String], root: URL) -> DatabaseSettings? {
        if let url = env["DATABASE_URL"] ?? env["DB_URL"], !url.isEmpty,
           var settings = parse(url: url, root: root) {
            settings.source = env["DATABASE_URL"] != nil ? "DATABASE_URL" : "DB_URL"
            return settings
        }
        guard let connection = env["DB_CONNECTION"], !connection.isEmpty else { return nil }
        let dialect = normalizedDialect(connection)
        var settings = DatabaseSettings(dialect: dialect, source: "DB_* in .env")
        if dialect == "sqlite" {
            let path = env["DB_DATABASE"] ?? "database/database.sqlite"
            settings.filePath = path.hasPrefix("/") ? path : root.appendingPathComponent(path).path
            return settings
        }
        settings.host = env["DB_HOST"] ?? "127.0.0.1"
        settings.port = env["DB_PORT"].flatMap(Int.init) ?? defaultPorts[dialect]
        settings.user = env["DB_USERNAME"] ?? ""
        settings.password = env["DB_PASSWORD"] ?? ""
        settings.database = env["DB_DATABASE"] ?? ""
        return settings
    }

    /// `mysql://u:p@h:3306/db?x=y`, `postgresql://…`, `sqlite:///%kernel.project_dir%/var/data.db`.
    static func parse(url raw: String, root: URL) -> DatabaseSettings? {
        let replaced = raw.replacingOccurrences(of: "%kernel.project_dir%", with: root.path)
        guard let schemeEnd = replaced.range(of: "://") else { return nil }
        let dialect = normalizedDialect(String(replaced[..<schemeEnd.lowerBound]))
        if dialect == "sqlite" {
            var path = String(replaced[schemeEnd.upperBound...])
            if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
            if path.hasPrefix("//") { path.removeFirst() }  // sqlite:////abs → /abs
            return DatabaseSettings(dialect: dialect, filePath: path.hasPrefix("/") ? path : root.appendingPathComponent(path).path,
                                    source: "")
        }
        guard let components = URLComponents(string: replaced) else { return nil }
        var settings = DatabaseSettings(dialect: dialect, source: "")
        settings.host = components.host ?? "127.0.0.1"
        settings.port = components.port ?? defaultPorts[dialect]
        settings.user = components.user?.removingPercentEncoding ?? components.user ?? ""
        settings.password = components.password?.removingPercentEncoding ?? components.password ?? ""
        settings.database = String(components.path.drop { $0 == "/" })
        return settings
    }

    static func normalizedDialect(_ name: String) -> String {
        switch name.lowercased() {
        case "pgsql", "postgres", "postgresql", "pdo-pgsql": "postgres"
        case "mysql", "mariadb", "mysql2", "pdo-mysql": "mysql"
        case "sqlsrv", "mssql", "sqlserver", "pdo-sqlsrv": "sqlserver"
        case "sqlite", "sqlite3", "pdo-sqlite": "sqlite"
        default: name.lowercased()
        }
    }

    /// Parses dotenv syntax: `KEY=value`, `export KEY=…`, quotes, `#` comments, `${VAR}` expansion.
    public static func parseDotEnv(_ text: String, inheriting base: [String: String] = [:]) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            var expand = true
            if let quote = value.first, quote == "\"" || quote == "'", let close = value.dropFirst().firstIndex(of: quote) {
                expand = quote == "\""
                value = String(value[value.index(after: value.startIndex)..<close])
            } else if let comment = value.range(of: " #") {
                value = value[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            if expand {
                let known = base.merging(result) { $1 }
                while let range = value.range(of: #"\$\{[A-Za-z_][A-Za-z0-9_]*\}"#, options: .regularExpression) {
                    let name = String(value[range].dropFirst(2).dropLast())
                    value.replaceSubrange(range, with: known[name] ?? "")
                }
            }
            result[key] = value
        }
        return result
    }
}
