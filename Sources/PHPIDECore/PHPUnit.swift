import Foundation

/// One test (or a data-provider group) in a PHPUnit / Pest run.
public struct TestResult: Sendable, Hashable, Identifiable {
    public enum Status: Sendable, Hashable { case running, passed, failed, skipped }

    /// Fully qualified test class (`Hello\Tests\GreeterTest`), or the Pest file.
    public let className: String
    /// `testGreet`, or `testAdd/same` for a data set of `testAdd`.
    public let name: String
    /// The test file, from the runner's location hint.
    public let file: String?
    public var status: Status
    public var elapsed: Double?
    public var output: String

    public var id: String { className + "::" + name }
    /// 1 for data sets (shown nested under their method).
    public var depth: Int { name.contains("/") ? 1 : 0 }
    public var shortName: String { String(name.split(separator: "/", maxSplits: 1).last ?? Substring(name)) }
    /// The method name (`testAdd` for `testAdd/same`).
    public var methodName: String { String(name.split(separator: "/", maxSplits: 1).first ?? Substring(name)) }
}

/// Aggregates a `phpunit --teamcity` (or `pest --teamcity`) stream into per-test results.
public struct TestReport: Sendable {
    public private(set) var tests: [TestResult] = []
    /// Lines that weren't TeamCity messages and arrived outside any test (headers, fatal errors, summary).
    public private(set) var buildOutput = ""
    private var index: [String: Int] = [:]
    private var currentClass = ""
    private var currentFile: String?
    /// The data-provider method whose data sets are running.
    private var currentGroup: String?
    private var running: Int?

    public init() {}

    public var passed: Int { leaves.filter { $0.status == .passed }.count }
    public var failed: Int { leaves.filter { $0.status == .failed }.count }
    public var skipped: Int { leaves.filter { $0.status == .skipped }.count }
    /// Real tests (data-provider group rows excluded).
    private var leaves: [TestResult] {
        tests.filter { test in !(test.depth == 0 && tests.contains { $0.depth == 1 && $0.className == test.className && $0.methodName == test.name }) }
    }

    public mutating func consume(line: String) {
        guard let message = TeamCityMessage(line) else {
            if let running { tests[running].output += line + "\n" } else if !line.isEmpty { buildOutput += line + "\n" }
            return
        }
        let name = message["name"] ?? ""
        switch message.kind {
        case "testSuiteStarted":
            guard let hint = message["locationHint"].flatMap(Self.location) else { return }
            if let method = hint.method {
                currentGroup = method
                _ = slot(className: hint.className, name: method, file: hint.file)
            } else {
                currentClass = hint.className
                currentFile = hint.file
            }
        case "testSuiteFinished":
            if let group = currentGroup, name == group {
                finishGroup(group)
                currentGroup = nil
            }
        case "testStarted":
            let hint = message["locationHint"].flatMap(Self.location)
            let className = hint?.className ?? currentClass
            var testName = name
            if let group = currentGroup, name.hasPrefix(group + " with data set ") {
                var label = String(name.dropFirst(group.count + " with data set ".count))
                if label.hasPrefix("\""), label.hasSuffix("\""), label.count >= 2 { label = String(label.dropFirst().dropLast()) }
                testName = group + "/" + label
            }
            running = slot(className: className, name: testName, file: hint?.file ?? currentFile)
            tests[running!].status = .running
        case "testFailed":
            guard let i = running else { return }
            tests[i].status = .failed
            let text = [message["message"], message["details"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            tests[i].output += text.hasSuffix("\n") ? text : text + "\n"
        case "testIgnored":
            guard let i = running else { return }
            tests[i].status = .skipped
            if let reason = message["message"], !reason.isEmpty { tests[i].output += "Skipped: \(reason)\n" }
        case "testFinished":
            guard let i = running else { return }
            if tests[i].status == .running { tests[i].status = .passed }
            if let ms = message["duration"].flatMap(Double.init) { tests[i].elapsed = ms / 1000 }
            running = nil
        default:
            break
        }
    }

    /// Marks anything still running as failed (the runner died mid-test).
    public mutating func finish() {
        for i in tests.indices where tests[i].status == .running { tests[i].status = .failed }
        running = nil
    }

    private mutating func slot(className: String, name: String, file: String?) -> Int {
        let key = className + "::" + name
        if let i = index[key] { return i }
        tests.append(TestResult(className: className, name: name, file: file, status: .running, elapsed: nil, output: ""))
        index[key] = tests.count - 1
        return tests.count - 1
    }

    private mutating func finishGroup(_ method: String) {
        guard let i = tests.lastIndex(where: { $0.name == method && $0.depth == 0 }) else { return }
        let children = tests.filter { $0.depth == 1 && $0.className == tests[i].className && $0.methodName == method }
        tests[i].status = children.contains { $0.status == .failed } ? .failed
            : children.contains { $0.status == .passed } ? .passed : .skipped
        tests[i].elapsed = children.compactMap(\.elapsed).reduce(0, +)
    }

    /// `php_qn:///path/FooTest.php::\NS\FooTest::method` (or `pest_qn://…`).
    static func location(_ hint: String) -> (file: String, className: String, method: String?)? {
        guard let schemeEnd = hint.range(of: "://") else { return nil }
        let parts = hint[schemeEnd.upperBound...].components(separatedBy: "::")
        guard parts.count >= 2 else { return nil }
        var className = parts[1]
        if className.hasPrefix("\\") { className.removeFirst() }
        return (parts[0], className, parts.count >= 3 ? parts[2...].joined(separator: "::") : nil)
    }
}

/// `##teamcity[kind key='value' …]` with TeamCity escapes (`|'`, `|n`, `||`, `|[`, `|]`).
struct TeamCityMessage {
    let kind: String
    private let attributes: [String: String]

    subscript(key: String) -> String? { attributes[key] }

    init?(_ line: String) {
        guard let start = line.range(of: "##teamcity["), line.hasSuffix("]") else { return nil }
        let body = Array(line[start.upperBound..<line.index(before: line.endIndex)])
        var i = 0
        var kind = ""
        while i < body.count, body[i] != " " { kind.append(body[i]); i += 1 }
        var attributes: [String: String] = [:]
        while i < body.count {
            while i < body.count, body[i] == " " { i += 1 }
            var key = ""
            while i < body.count, body[i] != "=" { key.append(body[i]); i += 1 }
            i += 2  // ='
            var value = ""
            while i < body.count, body[i] != "'" {
                if body[i] == "|", i + 1 < body.count {
                    i += 1
                    switch body[i] {
                    case "n": value.append("\n")
                    case "r": value.append("\r")
                    default: value.append(body[i])  // | ' [ ]
                    }
                } else {
                    value.append(body[i])
                }
                i += 1
            }
            i += 1
            if !key.isEmpty { attributes[key] = value }
        }
        guard !kind.isEmpty else { return nil }
        self.kind = kind
        self.attributes = attributes
    }
}

/// Finds PHPUnit test methods in source text.
public enum PHPTestFinder {
    private static let method = try! NSRegularExpression(
        pattern: #"^[ \t]*((?:(?:public|protected|private|static|final|abstract)[ \t]+)*)function[ \t]+&?([A-Za-z_]\w*)[ \t]*\("#,
        options: .anchorsMatchLines)

    public static func isTestFile(_ name: String) -> Bool {
        name.hasSuffix("Test.php")
    }

    /// Test methods (`test*`, `#[Test]`, `@test`) with their zero-based declaration lines.
    public static func testMethods(in text: String) -> [(name: String, line: Int)] {
        methods(in: text).filter(\.isTest).map { ($0.name, $0.line) }
    }

    /// The test method whose body contains `offset` (the nearest method declared above it).
    public static func enclosingTest(in text: String, at offset: Int) -> String? {
        let last = methods(in: text).last { $0.location <= offset }
        return last?.isTest == true ? last?.name : nil
    }

    /// `Namespace\ClassName` declared in `text`, for `--filter`.
    public static func className(in text: String) -> String? {
        let ns = text as NSString
        func first(_ pattern: String) -> String? {
            let regex = try! NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
            return regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        }
        guard let name = first(#"^\s*(?:(?:final|abstract|readonly)\s+)*class\s+(\w+)"#) else { return nil }
        return first(#"^\s*namespace\s+([\w\\]+)\s*;"#).map { $0 + "\\" + name } ?? name
    }

    private static func methods(in text: String) -> [(name: String, line: Int, location: Int, isTest: Bool)] {
        let ns = text as NSString
        let index = LineIndex(text)
        return method.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            let modifiers = ns.substring(with: match.range(at: 1))
            let name = ns.substring(with: match.range(at: 2))
            let isPublic = !modifiers.contains("private") && !modifiers.contains("protected") && !modifiers.contains("static")
            let isTest = isPublic && (name.hasPrefix("test") || annotatedAsTest(ns, before: match.range.location))
            return (name, index.position(of: match.range.location).line, match.range.location, isTest)
        }
    }

    /// `#[Test]` / `@test` in the attributes and doc comment right above a declaration.
    private static func annotatedAsTest(_ ns: NSString, before location: Int) -> Bool {
        let head = ns.substring(to: location)
        var lines = head.split(separator: "\n", omittingEmptySubsequences: false).dropLast().reversed().makeIterator()
        while let line = lines.next() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix("#[") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/**") || trimmed.hasSuffix("*/") else { return false }
            if trimmed.range(of: #"#\[\s*(?:\\?PHPUnit\\Framework\\Attributes\\)?Test\s*[\](,]"#, options: .regularExpression) != nil
                || trimmed.range(of: #"@test\b"#, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}

/// Which test runner a project uses and how to call it.
public enum PHPTestRunner {
    /// `vendor/bin/pest`, else `vendor/bin/phpunit`, else a global `phpunit`.
    public static func locate(in root: URL, find: (String) -> URL? = { ToolLocator.find($0) }) -> URL? {
        for name in ["pest", "phpunit"] {
            let local = root.appendingPathComponent("vendor/bin/\(name)")
            if FileManager.default.isExecutableFile(atPath: local.path) { return local }
        }
        return find("phpunit")
    }

    /// Arguments for `--teamcity` runs: everything, one file, or one test method (all its data sets).
    public static func arguments(root: URL, file: String? = nil, className: String? = nil, method: String? = nil) -> [String] {
        var args = ["--teamcity"]
        if let method {
            let qualified = className.map { NSRegularExpression.escapedPattern(for: $0) + "::" } ?? "::"
            args += ["--filter", "/" + qualified + NSRegularExpression.escapedPattern(for: method) + "( with data set .*)?$/"]
        }
        if let file {
            args.append(file)
        } else {
            let configs = ["phpunit.xml", "phpunit.xml.dist", "phpunit.dist.xml"]
            let hasConfig = configs.contains { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
            if !hasConfig, FileManager.default.fileExists(atPath: root.appendingPathComponent("tests").path) { args.append("tests") }
        }
        return args
    }
}
