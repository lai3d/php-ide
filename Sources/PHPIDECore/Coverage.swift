import Foundation

/// Line coverage from a PHPUnit Clover report, mapped to files on disk.
public struct CoverageReport: Sendable, Hashable {
    public struct FileCoverage: Sendable, Hashable {
        /// Zero-based line → covered (true) / not covered (false). Lines without statements are absent.
        public var lines: [Int: Bool] = [:]
        public var statements = 0
        public var coveredStatements = 0

        public var percent: Double {
            statements == 0 ? 0 : Double(coveredStatements) / Double(statements) * 100
        }
    }

    /// Keyed by absolute file path.
    public var files: [String: FileCoverage] = [:]

    public var percent: Double {
        let total = files.values.reduce(0) { $0 + $1.statements }
        let covered = files.values.reduce(0) { $0 + $1.coveredStatements }
        return total == 0 ? 0 : Double(covered) / Double(total) * 100
    }

    public init() {}

    /// Parses a PHPUnit Clover report (`--coverage-clover`): `<file name="…"><line num="12" type="stmt" count="3"/>`.
    /// Paths go through `normalize` (e.g. symlink resolution) so they match the editor's keys.
    public static func parseClover(_ data: Data, normalize: (String) -> String = { $0 }) -> CoverageReport {
        let delegate = CloverParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        var report = CoverageReport()
        for (path, lines) in delegate.files {
            var file = FileCoverage()
            for (line, count) in lines {
                file.lines[line - 1] = count > 0
                file.statements += 1
                if count > 0 { file.coveredStatements += 1 }
            }
            report.files[normalize(path)] = file
        }
        return report
    }
}

private final class CloverParser: NSObject, XMLParserDelegate {
    var files: [String: [Int: Int]] = [:]
    private var current: String?

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "file":
            current = attributes["name"]
            if let current, files[current] == nil { files[current] = [:] }
        case "line":
            // Statement lines carry coverage; "method" lines just mark declarations.
            guard let current, attributes["type"] == "stmt",
                  let num = attributes["num"].flatMap(Int.init), let count = attributes["count"].flatMap(Int.init) else { return }
            let previous = files[current]?[num] ?? 0
            files[current, default: [:]][num] = max(previous, count)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "file" { current = nil }
    }
}
