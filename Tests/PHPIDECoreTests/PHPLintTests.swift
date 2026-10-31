import Foundation
import Testing
@testable import PHPIDECore

@Suite struct PHPLintTests {
    @Test func parsesAndDedupesParseErrors() throws {
        let output = """
            PHP Parse error:  syntax error, unexpected token "{", expecting variable in /p/a b.php on line 2
            Parse error: syntax error, unexpected token "{", expecting variable in /p/a b.php on line 2
            Errors parsing /p/a b.php
            No syntax errors detected in /p/ok.php
            """
        let result = PHPLint.parse(output)
        let list = try #require(result["/p/a b.php"])
        #expect(result.count == 1 && list.count == 1)
        #expect(list[0].message == #"syntax error, unexpected token "{", expecting variable"#)
        #expect(list[0].start == TextPosition(line: 1, character: 0) && list[0].source == "php -l")
    }

    @Test(.enabled(if: ToolLocator.find("php") != nil), .timeLimit(.minutes(1)))
    func lintsFilesConcurrently() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-lint-\(UUID().uuidString)").canonicalFileURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var files: [String] = []
        for i in 0..<10 {
            let url = dir.appendingPathComponent("f\(i).php")
            try (i % 4 == 0 ? "<?php\nfunction f( {\n" : "<?php\necho \(i);\n").write(to: url, atomically: true, encoding: .utf8)
            files.append(url.path)
        }
        let found = await PHPLint.lint(files: files, php: try #require(ToolLocator.find("php")))
        #expect(found.keys.map { ($0 as NSString).lastPathComponent }.sorted() == ["f0.php", "f4.php", "f8.php"])
    }
}
