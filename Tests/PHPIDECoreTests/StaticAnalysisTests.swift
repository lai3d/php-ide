import Foundation
import Testing
@testable import PHPIDECore

@Suite struct StaticAnalysisTests {
    let root = URL(fileURLWithPath: "/proj")

    @Test func parsesPHPStanJSONAfterBannerText() throws {
        let output = """
            Instructions for interpreting errors {not json
            {"totals":{"errors":0,"file_errors":2},"files":{"/proj/src/a.php":{"errors":2,"messages":[\
            {"message":"Function g not found.","line":3,"ignorable":true,"identifier":"function.notFound"},\
            {"message":"Has \\"quotes\\" and } brace","line":1}]},\
            "/proj/src/T.php (in context of class X)":{"errors":1,"messages":[{"message":"Trait issue","line":9}]}},"errors":[]}
            trailing text
            """
        let result = try #require(StaticAnalyzer.phpstan.parse(output, root: root))
        let a = try #require(result["/proj/src/a.php"])
        #expect(a.map(\.message) == ["Function g not found. [function.notFound]", #"Has "quotes" and } brace"#])
        #expect(a[0].start == TextPosition(line: 2, character: 0) && a[0].source == "phpstan")
        #expect(result["/proj/src/T.php"]?.first?.start.line == 8)
        #expect(StaticAnalyzer.phpstan.parse("Fatal: no config", root: root) == nil)
    }

    @Test func parsesPsalmJSON() throws {
        let output = #"[{"severity":"error","line_from":4,"line_to":4,"type":"UndefinedFunction","message":"Function g does not exist","file_name":"src/a.php","file_path":"/proj/src/a.php","column_from":6,"column_to":9},{"severity":"info","line_from":1,"line_to":2,"type":"MissingReturnType","message":"No return type","file_name":"b.php","column_from":1,"column_to":2}]"#
        let result = try #require(StaticAnalyzer.psalm.parse(output, root: root))
        let a = try #require(result["/proj/src/a.php"]?.first)
        #expect(a.severity == .error && a.start == TextPosition(line: 3, character: 5) && a.end == TextPosition(line: 3, character: 8))
        #expect(a.message == "Function g does not exist [UndefinedFunction]")
        #expect(result["/proj/b.php"]?.first?.severity == .warning)
    }

    @Test func prefersAConfiguredAnalyzer() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-sa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let both = { (name: String) -> URL? in URL(fileURLWithPath: "/bin/\(name)") }
        #expect(StaticAnalyzer.preferred(in: dir, find: both)?.0 == .phpstan)
        #expect(StaticAnalyzer.phpstan.arguments(in: dir).suffix(1) == ["src"])
        try "<psalm/>".write(to: dir.appendingPathComponent("psalm.xml"), atomically: true, encoding: .utf8)
        #expect(StaticAnalyzer.preferred(in: dir, find: both)?.0 == .psalm)
        #expect(StaticAnalyzer.preferred(in: dir, find: { _ in nil }) == nil)
    }
}
