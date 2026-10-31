import Foundation
import Testing
@testable import PHPIDECore

/// A live Intelephense on a temp project, for exercising PHPIDECore's LSP parsing against real answers.
final class PHPServerSession: @unchecked Sendable {
    let client = LSPClient()
    let dir: URL
    private let diagnostics: AsyncStream<(String, [Diagnostic])>
    private let indexed: AsyncStream<Void>

    static var available: Bool { ToolLocator.find("intelephense") != nil }

    init(files: [String: String], capabilities: JSONValue = [:]) async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-lsp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dir = base.canonicalFileURL
        for (path, text) in files {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let (diagnostics, diagnosticsSink) = AsyncStream<(String, [Diagnostic])>.makeStream()
        let (indexed, indexedSink) = AsyncStream<Void>.makeStream()
        self.diagnostics = diagnostics
        self.indexed = indexed
        client.onNotification = { method, params in
            if method == "indexingEnded" { indexedSink.yield() }
            if method == "textDocument/publishDiagnostics", let published = Diagnostic.parsePublish(params) {
                diagnosticsSink.yield((published.uri, published.diagnostics))
            }
        }
        let server = try #require(PHPLanguageServer.locate(preferred: .intelephense))
        try client.start(executable: server.executable, arguments: server.arguments,
                         environment: ToolLocator.environment(), currentDirectory: dir)
        _ = try await client.request("initialize", params: [
            "processId": .int(Int(getpid())), "rootUri": .string(dir.absoluteString),
            "workspaceFolders": [["uri": .string(dir.absoluteString), "name": "t"]],
            "initializationOptions": PHPLanguageServer.initializationOptions(for: .intelephense),
            "capabilities": capabilities,
        ])
        try client.notify("initialized", params: [:])
        for await _ in self.indexed { break }  // cross-file answers need the index
    }

    func uri(_ path: String) -> String { dir.appendingPathComponent(path).absoluteString }

    func open(_ path: String) throws {
        let text = try String(contentsOf: dir.appendingPathComponent(path), encoding: .utf8)
        try client.notify("textDocument/didOpen", params: [
            "textDocument": ["uri": .string(uri(path)), "languageId": "php", "version": 1, "text": .string(text)],
        ])
    }

    func at(_ path: String, _ line: Int, _ character: Int) -> JSONValue {
        ["textDocument": ["uri": .string(uri(path))], "position": TextPosition(line: line, character: character).json]
    }

    /// The next non-empty diagnostics published for `path`.
    func nextDiagnostics(for path: String) async -> [Diagnostic] {
        for await (uri, list) in diagnostics where uri == self.uri(path) && !list.isEmpty { return list }
        return []
    }

    func close() async {
        await client.shutdown()
        try? FileManager.default.removeItem(at: dir)
    }
}

@Suite(.serialized) struct IntelephenseTests {
    static let greeter = """
        <?php

        namespace App;

        class Greeter
        {
            public string $greeting = 'Hello';

            /** Greets someone by name. */
            public function greet(string $name, int $times = 1): string
            {
                return str_repeat("$this->greeting, $name! ", $times);
            }
        }

        """
    static let main = """
        <?php

        use App\\Greeter;

        $greeter = new Greeter();
        echo $greeter->greet('Ada', 2);
        echo $greeter->greet('Linus');
        $greeter->gr

        """

    @Test(.enabled(if: PHPServerSession.available), .timeLimit(.minutes(1)))
    func publishesDiagnosticsForBrokenCode() async throws {
        let session = try await PHPServerSession(files: ["broken.php": "<?php\n\nfunction f(): int {\n    return\n"])
        try session.open("broken.php")
        let diagnostics = await session.nextDiagnostics(for: "broken.php")
        #expect(diagnostics.contains { $0.severity == .error && $0.start.line >= 3 }, "\(diagnostics.map(\.message))")
        await session.close()
    }

    @Test(.enabled(if: PHPServerSession.available), .timeLimit(.minutes(1)))
    func completionHoverAndDefinition() async throws {
        let session = try await PHPServerSession(
            files: ["src/Greeter.php": Self.greeter, "index.php": Self.main],
            capabilities: ["textDocument": ["hover": ["contentFormat": ["markdown"]],
                                            "completion": ["completionItem": ["snippetSupport": true]]]])
        try session.open("index.php")

        // `$greeter->gr|` on line 7
        let items = CompletionItem.parseList(try await session.client.request("textDocument/completion", params: session.at("index.php", 7, 12)))
        #expect(items.contains { $0.label == "greet" }, "\(items.map(\.label))")
        #expect(items.allSatisfy { FuzzyMatch.matches("gr", $0.filterText) })

        // Hover on `greet` (line 5): signature and doc comment
        let hover = try #require(HoverContent.parse(try await session.client.request("textDocument/hover", params: session.at("index.php", 5, 17))))
        #expect(hover.contains("function greet(string $name, int $times = 1): string"), "\(hover)")
        #expect(hover.contains("Greets someone by name."))

        // Definition of `greet` → src/Greeter.php line 9; of `Greeter` → line 4
        let method = Location.parseAll(try await session.client.request("textDocument/definition", params: session.at("index.php", 5, 17)))
        // Intelephense spans the whole declaration, starting at its doc comment (line 8).
        #expect(method.first?.uri.hasSuffix("/src/Greeter.php") == true && method.first?.start.line == 8, "\(method)")
        let type = Location.parseAll(try await session.client.request("textDocument/definition", params: session.at("index.php", 4, 16)))
        #expect(type.first?.start.line == 4)
        await session.close()
    }

    @Test(.enabled(if: PHPServerSession.available), .timeLimit(.minutes(1)))
    func documentAndWorkspaceSymbols() async throws {
        let session = try await PHPServerSession(
            files: ["src/Greeter.php": Self.greeter],
            capabilities: ["textDocument": ["documentSymbol": ["hierarchicalDocumentSymbolSupport": true]]])
        try session.open("src/Greeter.php")
        let outline = SymbolNode.parseAll(try await session.client.request("textDocument/documentSymbol", params: [
            "textDocument": ["uri": .string(session.uri("src/Greeter.php"))],
        ]))
        let names = outline.flatMap { [$0.name] + ($0.children ?? []).flatMap { [$0.name] + ($0.children ?? []).map(\.name) } }
        #expect(names.contains { $0.hasSuffix("Greeter") } && names.contains("greet"), "\(names)")

        let symbols = SymbolNode.parseAll(try await session.client.request("workspace/symbol", params: ["query": "Greeter"]))
        #expect(symbols.contains { $0.name.hasSuffix("Greeter") && $0.uri?.hasSuffix("/src/Greeter.php") == true })
        await session.close()
    }

    @Test(.enabled(if: PHPServerSession.available), .timeLimit(.minutes(1)))
    func findsReferencesAcrossFiles() async throws {
        let session = try await PHPServerSession(files: ["src/Greeter.php": Self.greeter, "index.php": Self.main])
        try session.open("index.php")
        var params = session.at("index.php", 5, 17)
        if case .object(var object) = params { object["context"] = ["includeDeclaration": true]; params = .object(object) }
        let locations = Location.parseAll(try await session.client.request("textDocument/references", params: params))
        #expect(locations.count == 3, "\(locations)")  // declaration + two calls
        #expect(locations.contains { $0.uri.hasSuffix("/src/Greeter.php") && $0.start.line == 9 })
        await session.close()
    }

    @Test(.enabled(if: PHPServerSession.available), .timeLimit(.minutes(1)))
    func highlightsOccurrences() async throws {
        let source = "<?php\n\n$total = 1;\n$total = $total + 2;\necho $total;\n"
        let session = try await PHPServerSession(files: ["index.php": source])
        try session.open("index.php")
        let highlights = DocumentHighlight.parseAll(try await session.client.request("textDocument/documentHighlight",
                                                                                      params: session.at("index.php", 4, 7)))
        #expect(highlights.count == 4, "\(highlights)")
        #expect(Set(highlights.map(\.start.line)) == [2, 3, 4])
        await session.close()
    }

    @Test(.enabled(if: PHPServerSession.available), .timeLimit(.minutes(1)))
    func signatureHelpTracksTheActiveParameter() async throws {
        let session = try await PHPServerSession(
            files: ["src/Greeter.php": Self.greeter, "index.php": Self.main],
            capabilities: ["textDocument": ["signatureHelp": ["signatureInformation": [
                "parameterInformation": ["labelOffsetSupport": true]]]]])
        try session.open("index.php")
        // `echo $greeter->greet('Ada'|, |2);` on line 5
        let first = try #require(SignatureHelp.parse(try await session.client.request("textDocument/signatureHelp", params: session.at("index.php", 5, 22))))
        let label = try #require(first.active?.label) as NSString
        #expect(label.substring(with: try #require(first.activeParameterRange)).contains("$name"), "\(label)")
        let second = try #require(SignatureHelp.parse(try await session.client.request("textDocument/signatureHelp", params: session.at("index.php", 5, 29))))
        let secondLabel = try #require(second.active?.label) as NSString
        #expect(secondLabel.substring(with: try #require(second.activeParameterRange)).contains("$times"), "\(secondLabel)")
        await session.close()
    }
}
