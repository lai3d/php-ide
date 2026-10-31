import Foundation

/// `php -l` syntax checking.
public enum PHPLint {
    public static let source = "php -l"

    private static let regex = try! NSRegularExpression(
        pattern: #"^(?:PHP )?(Parse|Fatal|Compile) error:\s+(.*) in (.+) on line (\d+)\s*$"#)

    /// Parse errors in `php -l` output (stdout + stderr), keyed by file path; duplicates
    /// (PHP logs the same error to both streams) are dropped.
    public static func parse(_ output: String) -> [String: [Diagnostic]] {
        var result: [String: [Diagnostic]] = [:]
        var seen = Set<String>()
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let number = Int(ns.substring(with: match.range(at: 4)))
            else { continue }
            let message = ns.substring(with: match.range(at: 2))
            let file = ns.substring(with: match.range(at: 3))
            guard seen.insert("\(file):\(number):\(message)").inserted else { continue }
            let position = TextPosition(line: max(number - 1, 0), character: 0)
            result[file, default: []].append(Diagnostic(start: position, end: position, severity: .error,
                                                        message: message, source: source))
        }
        return result
    }

    /// Lints `files` with `php -l`, a few at a time, and returns the parse errors by path.
    public static func lint(files: [String], php: URL, concurrency: Int = 6) async -> [String: [Diagnostic]] {
        await withTaskGroup(of: [String: [Diagnostic]].self) { group in
            var pending = files[...]
            var result: [String: [Diagnostic]] = [:]
            func next() {
                guard let file = pending.popFirst() else { return }
                group.addTask {
                    let output = await ProcessRunner.run(php, ["-d", "display_errors=stderr", "-l", file]).output
                    return parse(output)
                }
            }
            for _ in 0..<concurrency { next() }
            for await partial in group {
                result.merge(partial) { $0 + $1 }
                next()
            }
            return result
        }
    }
}

/// Runs a process to completion off the main thread, collecting stdout + stderr.
public enum ProcessRunner {
    public struct Result: Sendable {
        public let status: Int32
        public let output: String
    }

    public static func run(_ executable: URL, _ arguments: [String], in directory: URL? = nil,
                           environment: [String: String]? = nil) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let directory { process.currentDirectoryURL = directory }
            process.environment = environment ?? ToolLocator.environment()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let collected = DataBox()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil } else { collected.append(data) }
            }
            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
                continuation.resume(returning: Result(status: proc.terminationStatus,
                                                      output: String(decoding: collected.data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(status: -1, output: error.localizedDescription))
            }
        }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        var data: Data { lock.withLock { storage } }
        func append(_ more: Data) { lock.withLock { storage.append(more) } }
    }
}
