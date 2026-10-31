import Foundation
import Testing
@testable import PHPIDE
import PHPIDECore

@MainActor
@Suite struct WorkspaceTabTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-tabs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["a.php", "b.php", "c.php"] {
            try "<?php\n".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    @Test func openingTheSameFileReusesItsTab() {
        let workspace = Workspace()
        let first = workspace.openFile(url("a.php"))
        workspace.openFile(url("b.php"))
        let again = workspace.openFile(url("a.php"))
        #expect(first === again)
        #expect(workspace.documents.map(\.name) == ["a.php", "b.php"])
        #expect(workspace.activeDocument === first)
    }

    @Test func newTabsOpenNextToTheActiveOne() {
        let workspace = Workspace()
        let a = workspace.openFile(url("a.php"))!
        workspace.openFile(url("b.php"))
        workspace.activate(a)
        workspace.openFile(url("c.php"))
        #expect(workspace.documents.map(\.name) == ["a.php", "c.php", "b.php"])
    }

    @Test func closingTheActiveTabSelectsItsNeighbour() {
        let workspace = Workspace()
        workspace.openFile(url("a.php"))
        let b = workspace.openFile(url("b.php"))!
        workspace.openFile(url("c.php"))
        workspace.activate(b)
        workspace.closeDocument(b)
        #expect(workspace.documents.map(\.name) == ["a.php", "c.php"])
        #expect(workspace.activeDocument?.name == "c.php")
        workspace.closeAllDocuments()
        #expect(workspace.documents.isEmpty && workspace.activeDocument == nil)
    }

    @Test func cyclesTabs() {
        let workspace = Workspace()
        workspace.openFile(url("a.php"))
        workspace.openFile(url("b.php"))
        workspace.selectAdjacentTab(1)
        #expect(workspace.activeDocument?.name == "a.php")
        workspace.selectAdjacentTab(-1)
        #expect(workspace.activeDocument?.name == "b.php")
    }

    @Test func editsMarkDirtyAndSaveWritesToDisk() throws {
        let workspace = Workspace()
        let a = workspace.openFile(url("a.php"))!
        workspace.updateText(of: a, to: "<?php\n\nfunction x() {}\n")
        #expect(a.isDirty)
        workspace.save(a)
        #expect(!a.isDirty)
        #expect(try String(contentsOf: url("a.php"), encoding: .utf8).contains("function x()"))
    }
}

@MainActor
@Suite struct WorkspaceFormattingTests {
    @Test(.enabled(if: PHPIDECore.ToolLocator.find("intelephense") != nil), .timeLimit(.minutes(1)))
    func formatsOnSave() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-wsfmt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        let file = dir.appendingPathComponent("index.php")
        try "<?php\nfunction main(){\necho   \"hi\";\n}\n".write(to: file, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        let document = try #require(workspace.activeDocument)
        #expect(workspace.lspStatus.hasPrefix("intelephense: "))

        await workspace.format(document)
        #expect(document.isDirty)  // formatted in memory, not yet saved
        await workspace.saveFormatted(document)
        #expect(!document.isDirty)
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved == "<?php\nfunction main()\n{\n    echo   \"hi\";\n}\n")
    }
}

@MainActor
@Suite struct WorkspaceFileSystemTests {
    let dir: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-fs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("pkg"), withIntermediateDirectories: true)
        dir = base.canonicalFileURL  // real path, as FSEvents reports it
        try "{}\n".write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
        try "<?php\n\nfunction main() {}\n".write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        try "<?php\n".write(to: dir.appendingPathComponent("pkg/a.php"), atomically: true, encoding: .utf8)
    }

    private func url(_ path: String) -> URL { dir.appendingPathComponent(path) }

    @Test func reloadsCleanDocumentsAndFlagsDirtyOnes() async throws {
        let workspace = Workspace()
        await workspace.openFolder(dir.canonicalFileURL)
        let main = try #require(workspace.activeDocument)
        let other = try #require(workspace.openFile(url("pkg/a.php")))
        workspace.updateText(of: other, to: "<?php // edited\n")

        try "<?php\n\nfunction main() { echo 1; }\n".write(to: url("index.php"), atomically: true, encoding: .utf8)
        try "<?php // external\n".write(to: url("pkg/a.php"), atomically: true, encoding: .utf8)
        workspace.handleFileSystemChanges([url("index.php").path, url("pkg/a.php").path])

        #expect(main.text.contains("echo 1;") && !main.isDirty)
        #expect(other.text.contains("edited") && other.hasExternalChange)
        workspace.reloadFromDisk(other)
        #expect(other.text.contains("external") && !other.isDirty && !other.hasExternalChange)
    }

    @Test func createsRenamesAndTrashes() async throws {
        let workspace = Workspace()
        await workspace.openFolder(dir.canonicalFileURL)

        let created = try workspace.createFile(named: "b.php", in: url("pkg"))
        #expect(try String(contentsOf: created, encoding: .utf8) == "<?php\n\ndeclare(strict_types=1);\n\n")
        #expect(workspace.activeDocument?.name == "b.php")
        #expect(throws: FileOperationError.self) { try workspace.createFile(named: "b.php", in: url("pkg")) }

        let renamed = try workspace.renameItem(at: url("pkg"), to: "widgets")
        #expect(workspace.activeDocument?.url.path == renamed.appendingPathComponent("b.php").path)
        #expect(workspace.fileTree.contains { $0.name == "widgets" })

        try workspace.trashItem(at: renamed)
        #expect(!workspace.documents.contains { $0.name == "b.php" })
        #expect(!FileManager.default.fileExists(atPath: renamed.path))
    }

}

@MainActor
@Suite struct WorkspaceSearchTests {
    @Test func searchesProjectIncludingUnsavedBuffers() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-ws-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try "package main\n\nfunc main() { greet() }\n".write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        try "package main\n\nfunc greet() {}\n".write(to: dir.appendingPathComponent("greet.go"), atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        workspace.searchQuery = "greet"
        await workspace.performSearch()
        #expect(workspace.searchMatchCount == 2)

        // Edit greet.go without saving: the search sees the buffer.
        let greet = try #require(workspace.openFile(dir.appendingPathComponent("greet.go")))
        workspace.updateText(of: greet, to: "package main\n\nfunc greet() {}\nfunc greetAgain() {}\n")
        await workspace.performSearch()
        #expect(workspace.searchMatchCount == 3)

        let file = try #require(workspace.searchResults.first { $0.path.hasSuffix("index.php") })
        workspace.open(file.matches[0], in: file)
        #expect(workspace.activeDocument?.name == "index.php")
        #expect(workspace.activeDocument?.revealTarget?.position == TextPosition(line: 2, character: 14))
        #expect(workspace.activeDocument?.revealTarget?.length == 5)

        workspace.searchOptions.regex = true
        workspace.searchQuery = "("
        await workspace.performSearch()
        #expect(workspace.searchError != nil && workspace.searchResults.isEmpty)
    }
}

@MainActor
@Suite struct WorkspaceReferencesTests {
    @Test(.enabled(if: PHPIDECore.ToolLocator.find("intelephense") != nil), .timeLimit(.minutes(1)))
    func findsReferencesAcrossFilesUsingBuffers() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-ws-refs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        let mainSource = "<?php\n\nrequire 'greet.php';\n\ngreet(); greet();\n"
        try mainSource.write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        try "<?php\n\nfunction greet(): void {}\n".write(to: dir.appendingPathComponent("greet.php"), atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        let main = try #require(workspace.activeDocument)
        #expect(main.name == "index.php")
        for _ in 0..<100 where workspace.isIndexing { try await Task.sleep(for: .milliseconds(100)) }
        #expect(!workspace.isIndexing)
        await workspace.findReferences(in: main, at: (mainSource as NSString).range(of: "greet()").location + 1)
        #expect(workspace.bottomTab == .references)
        #expect(workspace.referenceTitle == "3 references to ‘greet’")
        #expect(workspace.referenceResults.map { ($0.path as NSString).lastPathComponent } == ["greet.php", "index.php"])
    }
}

@MainActor
@Suite struct WorkspaceNavigationTests {
    @Test(.enabled(if: PHPIDECore.ToolLocator.find("intelephense") != nil), .timeLimit(.minutes(1)))
    func quickOpenFindsFilesAndSymbolsAndOutlineLoads() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-ws-nav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("src/Progress"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try "<?php\n\nnamespace App;\n\nclass Greeter\n{\n    public function hello(): void {}\n}\n"
            .write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        try "<?php\n".write(to: dir.appendingPathComponent("greet.php"), atomically: true, encoding: .utf8)
        try "<?php\n".write(to: dir.appendingPathComponent("src/Progress/Report.php"), atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        workspace.showQuickOpen()
        #expect(workspace.quickOpenItems.map(\.title) == ["index.php"])  // empty query: open tabs

        workspace.quickOpenQuery = "gre"
        workspace.updateQuickOpen()
        #expect(workspace.quickOpenItems.first?.title == "greet.php")
        // The server may still be indexing: re-ask, as typing would.
        for _ in 0..<12 where !workspace.quickOpenItems.contains(where: { $0.position != nil }) {
            try await Task.sleep(for: .milliseconds(1500))
            if !workspace.quickOpenItems.contains(where: { $0.position != nil }) { workspace.updateQuickOpen() }
        }
        let symbol = try #require(workspace.quickOpenItems.first { $0.title == "Greeter" })
        workspace.open(symbol)
        #expect(!workspace.isQuickOpenVisible)
        #expect(workspace.activeDocument?.revealTarget?.position.line == 4)

        await workspace.refreshOutline()
        #expect(workspace.outline.map(\.name).contains("Greeter"))
    }
}

@MainActor
@Suite struct WorkspaceGitTests {
    @Test(.enabled(if: PHPIDECore.ToolLocator.find("git") != nil), .timeLimit(.minutes(1)))
    func tracksBranchStatusesAndBases() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-ws-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        Git.run(["init", "-q", "-b", "feature"], in: dir)
        try "{}\n".write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
        try "<?php\n\nfunction main() {}\n".write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        Git.run(["add", "."], in: dir)
        Git.run(["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "init"], in: dir)
        try "<?php\n\n// changed\nfunction main() {}\n".write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        try "<?php\n".write(to: dir.appendingPathComponent("new.php"), atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        for _ in 0..<50 where workspace.gitBranch == nil { try await Task.sleep(for: .milliseconds(100)) }
        #expect(workspace.gitBranch == "feature")
        #expect(workspace.gitStatus(for: dir.appendingPathComponent("index.php")) == .modified)
        #expect(workspace.gitStatus(for: dir.appendingPathComponent("new.php")) == .untracked)
        #expect(workspace.gitStatus(for: dir.appendingPathComponent("composer.json")) == nil)
        let main = try #require(workspace.activeDocument)
        #expect(workspace.gitBase(for: main) == "<?php\n\nfunction main() {}\n")
        let changes = LineChanges.compute(base: workspace.gitBase(for: main)!, current: main.text)
        #expect(changes.lines == [2: .added])
    }
}

@MainActor
@Suite(.serialized) struct SessionRestoreTests {
    @Test func restoresTabsAndRecents() async throws {
        let suite = "phpide-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        SessionStore.defaults = defaults
        defer {
            SessionStore.defaults = .standard
            defaults.removePersistentDomain(forName: suite)
        }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        for name in ["index.php", "a.php", "b.php"] {
            try "<?php\n".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let first = Workspace()
        await first.openFolder(dir)
        #expect(first.documents.map(\.name) == ["index.php"])  // nothing saved yet: default file
        first.openFile(dir.appendingPathComponent("a.php"))
        first.openFile(dir.appendingPathComponent("b.php"))
        first.activate(first.documents[1])  // a.php
        await first.shutdown()

        let second = Workspace()
        await second.openFolder(dir)
        #expect(second.documents.map(\.name) == ["index.php", "a.php", "b.php"])
        #expect(second.activeDocument?.name == "a.php")
        // Other suites open folders concurrently and may record theirs too: check membership, not order.
        #expect(SessionStore.recentProjects.contains { $0.path == dir.path })
        await second.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceReplaceTests {
    @Test func replacesInOpenBuffersAndOnDisk() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-replace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try "<?php\n\ngetUser(); getName();\n".write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        let other = dir.appendingPathComponent("other.php")
        try "<?php\n\nfunction getUser() {}\nfunction getName() {}\n".write(to: other, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        let main = try #require(workspace.activeDocument)
        workspace.searchOptions = SearchOptions(regex: true)
        workspace.searchQuery = #"get(\w+)\("#
        workspace.replaceQuery = "fetch$1("
        await workspace.performSearch()
        #expect(workspace.searchMatchCount == 4)

        // One match first: the second call in index.php (still in the buffer).
        let mainResult = try #require(workspace.searchResults.first { $0.path.hasSuffix("index.php") })
        await workspace.replace(mainResult.matches[1], in: mainResult)
        #expect(main.text.contains("getUser(); fetchName()") && main.isDirty)

        #expect(await workspace.replaceAllInProject() == 3)
        #expect(main.text.contains("fetchUser(); fetchName()"))
        #expect(try String(contentsOf: other, encoding: .utf8) == "<?php\n\nfunction fetchUser() {}\nfunction fetchName() {}\n")
        #expect(workspace.searchMatchCount == 0)
    }
}

@MainActor
@Suite struct WorkspaceRunTests {
    @Test(.enabled(if: PHPIDECore.ToolLocator.find("php") != nil), .timeLimit(.minutes(1)))
    func runsTheSelectedScriptWithArgumentsAndEnvironment() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try "<?php\necho 'index';\n".write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        try "#!/usr/bin/env php\n<?php\necho 'hi ', $argv[1], ' ', getenv('GREETING'), PHP_EOL;\n"
            .write(to: dir.appendingPathComponent("bin/greet"), atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        #expect(workspace.runConfigurations.map(\.script) == ["index.php", "bin/greet"])
        workspace.runConfigurations[1].arguments = "\"big world\""
        workspace.runConfigurations[1].environment = "GREETING=hello"
        workspace.selectedRunConfigurationID = workspace.runConfigurations[1].id

        workspace.runSelectedConfiguration()
        for _ in 0..<100 where workspace.isRunning || !workspace.output.contains("exited") {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(workspace.output.hasPrefix("$ GREETING=… php bin/greet \"big world\"\n"))
        #expect(workspace.output.contains("hi big world hello"))
        #expect(workspace.output.contains("[process exited with status 0]"))
        await workspace.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceSyntaxCheckTests {
    @Test(.enabled(if: PHPIDECore.ToolLocator.find("php") != nil), .timeLimit(.minutes(1)))
    func reportsParseErrorsUntilTheFileIsEdited() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-lintws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try "<?php\necho 1;\n".write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        try "<?php\n\nif (true {\n".write(to: dir.appendingPathComponent("broken.php"), atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        await workspace.checkSyntax()
        let lint = workspace.allProblems.filter { $0.diagnostic.source == "php -l" }
        #expect(lint.map(\.fileName) == ["broken.php"])
        #expect(lint.first?.diagnostic.start.line == 2)
        #expect(workspace.bottomTab == .problems)

        let broken = try #require(workspace.openFile(dir.appendingPathComponent("broken.php")))
        #expect(workspace.diagnostics(for: broken).contains { $0.source == "php -l" })
        workspace.updateText(of: broken, to: "<?php\n\nif (true) {}\n")
        #expect(!workspace.diagnostics(for: broken).contains { $0.source == "php -l" })
        await workspace.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceAnalyzeTests {
    /// Uses a PHPStan installed in a scratch project; set PHPIDE_PHPSTAN_PROJECT to its folder.
    nonisolated static let project = ProcessInfo.processInfo.environment["PHPIDE_PHPSTAN_PROJECT"]

    @Test(.enabled(if: project != nil), .timeLimit(.minutes(1)))
    func runsPHPStanIntoProblems() async throws {
        let dir = URL(fileURLWithPath: try #require(Self.project)).canonicalFileURL
        let workspace = Workspace()
        await workspace.openFolder(dir)
        await workspace.analyze()
        let problems = workspace.allProblems.filter { $0.diagnostic.source == "phpstan" }
        #expect(!problems.isEmpty)
        #expect(problems.allSatisfy { $0.path.hasPrefix(dir.path + "/") })
        await workspace.shutdown()
    }
}

@MainActor
@Suite struct WorkspacePHPUnitTests {
    /// A Composer project with PHPUnit installed and a failing test; set PHPIDE_PHPUNIT_PROJECT to its folder.
    nonisolated static let project = ProcessInfo.processInfo.environment["PHPIDE_PHPUNIT_PROJECT"]

    private func run(_ workspace: Workspace, _ scope: TestScope) async throws {
        workspace.runTests(scope)
        for _ in 0..<300 where workspace.isRunning || !workspace.output.contains(" skipped — exit ") {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test(.enabled(if: project != nil), .timeLimit(.minutes(1)))
    func runsAllFileAndMethodScopes() async throws {
        let dir = URL(fileURLWithPath: try #require(Self.project)).canonicalFileURL
        let workspace = Workspace()
        await workspace.openFolder(dir)

        try await run(workspace, .all)
        let report = workspace.testReport
        #expect(report.passed >= 1 && report.failed >= 1)
        #expect(workspace.selectedTestID != nil)  // first failure preselected
        #expect(workspace.testStatuses["testGreet"] == .passed)

        let greeter = dir.appendingPathComponent("tests/GreeterTest.php")
        try await run(workspace, .file(greeter))
        #expect(workspace.testReport.tests.map(\.name) == ["testGreet"])

        try await run(workspace, .test("testAdd", in: dir.appendingPathComponent("tests/MoreTest.php")))
        #expect(workspace.testReport.tests.map(\.name) == ["testAdd", "testAdd/same", "testAdd/diff"])
        #expect(workspace.output.contains("--filter"))

        let failing = try #require(workspace.testReport.tests.first { $0.name == "testAdd/diff" })
        workspace.revealTest(failing)
        #expect(workspace.activeDocument?.name == "MoreTest.php")
        #expect(workspace.activeDocument?.revealTarget?.position.line == 12)
        await workspace.shutdown()
    }
}

/// End-to-end debugging through the Workspace: needs node, php with Xdebug, and the adapter
/// (PHPIDE_PHP_DEBUG_JS or an installed copy); the test case also needs PHPIDE_PHPUNIT_PROJECT.
@MainActor
@Suite(.serialized) struct WorkspaceDebugTests {
    nonisolated static let adapterReady = (ProcessInfo.processInfo.environment["PHPIDE_PHP_DEBUG_JS"] != nil
        || PHPDebugAdapter.installedScript() != nil) && PHPIDECore.ToolLocator.find("node") != nil

    private func waitForPause(_ workspace: Workspace) async throws -> ExecutionLocation {
        for _ in 0..<200 where workspace.executionLocation == nil && workspace.debugSession?.isActive != false {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try #require(workspace.executionLocation, "never paused; output:\n\(workspace.output)")
    }

    private func finish(_ workspace: Workspace) async throws {
        workspace.stopDebugging()
        for _ in 0..<100 where workspace.isDebugging { try await Task.sleep(for: .milliseconds(50)) }
        await workspace.shutdown()
    }

    @Test(.enabled(if: adapterReady && WorkspacePHPUnitTests.project != nil), .timeLimit(.minutes(1)))
    func debugsTheTestAtTheCaret() async throws {
        let dir = URL(fileURLWithPath: try #require(WorkspacePHPUnitTests.project)).canonicalFileURL
        let workspace = Workspace()
        await workspace.openFolder(dir)
        let test = try #require(workspace.openFile(dir.appendingPathComponent("tests/GreeterTest.php")))
        workspace.toggleBreakpoint(in: test, line: 13)  // the assertSame line (1-based 14)
        test.caretOffset = (test.text as NSString).range(of: "assertSame").location
        workspace.startDebugging()  // a test file with the caret in testGreet → debug(test:)
        let location = try await waitForPause(workspace)
        #expect(location.path.hasSuffix("/tests/GreeterTest.php") && location.line == 14)
        #expect(workspace.debugSession?.title == "testGreet")
        workspace.toggleBreakpoint(in: test, line: 13)
        try await finish(workspace)
    }

    @Test(.enabled(if: adapterReady && PHPIDECore.ToolLocator.find("php") != nil), .timeLimit(.minutes(1)))
    func listensForAnXdebugConnection() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-listen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        let script = dir.appendingPathComponent("index.php")
        try "<?php\n$who = 'web';\necho \"hello $who\\n\";\n".write(to: script, atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        let document = try #require(workspace.activeDocument)
        workspace.toggleBreakpoint(in: document, line: 2)
        let port = Int.random(in: 40000..<50000)
        workspace.listenForXdebug(port: port)
        #expect(workspace.output.contains("Waiting for Xdebug on 127.0.0.1:\(port)"))

        // A php run started "elsewhere" (here: a plain process) with Xdebug pointed at our port.
        let php = try #require(PHPIDECore.ToolLocator.find("php"))
        let xdebug = await Xdebug.status(php: php)
        // If the adapter isn't listening yet, Xdebug can't connect and php just runs to the end: start it again.
        var process = Process()
        defer { if process.isRunning { process.terminate() } }
        for _ in 0..<20 where workspace.executionLocation == nil {
            process = Process()
            process.executableURL = php
            process.arguments = xdebug.runtimeArguments + ["-dxdebug.client_port=\(port)", "-dxdebug.connect_timeout_ms=300", script.path]
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            for _ in 0..<40 where process.isRunning && workspace.executionLocation == nil {
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        let location = try await waitForPause(workspace)
        #expect(location.path == script.path && location.line == 3)
        try await finish(workspace)
    }
}

@MainActor
@Suite(.serialized) struct WorkspaceWebServerTests {
    private func makeSite() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-web-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("public"), withIntermediateDirectories: true)
        let dir = base.canonicalFileURL
        try "<?php\n$page = $_GET['p'] ?? 'home';\necho \"page=$page\";\n"
            .write(to: dir.appendingPathComponent("public/index.php"), atomically: true, encoding: .utf8)
        return dir
    }

    /// GETs `url`, retrying while the server starts.
    private func fetch(_ url: URL) async -> String? {
        for _ in 0..<40 {
            if let (data, _) = try? await URLSession.shared.data(from: url) { return String(decoding: data, as: UTF8.self) }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    @Test(.enabled(if: PHPIDECore.ToolLocator.find("php") != nil), .timeLimit(.minutes(1)))
    func servesThePublicFolder() async throws {
        let dir = try makeSite()
        defer { try? FileManager.default.removeItem(at: dir) }
        let workspace = Workspace()
        await workspace.openFolder(dir)
        let server = try #require(workspace.runConfigurations.first)
        #expect(server.kind == .server && server.documentRoot == "public")
        let port = Int.random(in: 50000..<55000)
        workspace.runConfigurations[0].port = port

        workspace.runSelectedConfiguration()
        #expect(workspace.output.contains("Serving http://127.0.0.1:\(port)/"))
        let body = await fetch(URL(string: "http://127.0.0.1:\(port)/?p=docs")!)
        #expect(body == "page=docs")
        workspace.stopRun()
        for _ in 0..<100 where workspace.isRunning { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!workspace.isRunning)
        await workspace.shutdown()
    }

    @Test(.enabled(if: WorkspaceDebugTests.adapterReady && PHPIDECore.ToolLocator.find("php") != nil), .timeLimit(.minutes(1)))
    func debugsARequestToTheWebServer() async throws {
        let dir = try makeSite()
        defer { try? FileManager.default.removeItem(at: dir) }
        let workspace = Workspace()
        await workspace.openFolder(dir)
        let port = Int.random(in: 55000..<60000)
        workspace.runConfigurations[0].port = port
        let index = try #require(workspace.openFile(dir.appendingPathComponent("public/index.php")))
        workspace.toggleBreakpoint(in: index, line: 2)  // echo line (1-based 3)

        workspace.debug(configuration: workspace.runConfigurations[0])
        let request = Task { await fetch(URL(string: "http://127.0.0.1:\(port)/?p=debug")!) }
        for _ in 0..<200 where workspace.executionLocation == nil { try await Task.sleep(for: .milliseconds(50)) }
        let location = try #require(workspace.executionLocation, "never paused; output:\n\(workspace.output)")
        #expect(location.path.hasSuffix("/public/index.php") && location.line == 3)

        workspace.debugSession?.resume()
        #expect(await request.value == "page=debug")
        workspace.stopDebugging()
        for _ in 0..<100 where workspace.isDebugging { try await Task.sleep(for: .milliseconds(50)) }
        await workspace.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceComposerScriptTests {
    @Test(.enabled(if: PHPIDECore.ToolLocator.find("composer") != nil), .timeLimit(.minutes(1)))
    func listsAndRunsComposerScripts() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-cscripts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try #"{"name": "t/t", "scripts": {"hello": "@php -r \"echo 'hi from composer';\""}}"#
            .write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
        let workspace = Workspace()
        await workspace.openFolder(dir)
        #expect(workspace.composerScripts == ["hello"])
        workspace.runTool("composer", ["run-script", "hello"])
        for _ in 0..<200 where workspace.isRunning || !workspace.output.contains("exited") { try await Task.sleep(for: .milliseconds(50)) }
        #expect(workspace.output.contains("hi from composer"))
        await workspace.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceCompletionTests {
    @Test(.enabled(if: PHPIDECore.ToolLocator.find("intelephense") != nil), .timeLimit(.minutes(1)))
    func completesVariablesMembersAndSnippets() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-compl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try "<?php\nclass Greeter { public function greet(): string { return ''; } }\n$greeter = new Greeter();\n"
            .write(to: dir.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        let workspace = Workspace()
        await workspace.openFolder(dir)
        let doc = try #require(workspace.activeDocument)
        for _ in 0..<100 where workspace.isIndexing { try await Task.sleep(for: .milliseconds(100)) }

        func items(after typed: String) async -> [CompletionItem] {
            workspace.updateText(of: doc, to: "<?php\nclass Greeter { public function greet(): string { return ''; } }\n$greeter = new Greeter();\n" + typed)
            return await workspace.completions(in: doc, at: (doc.text as NSString).length)
        }
        let variables = await items(after: "$gre")
        let greeter = try #require(variables.first { $0.label == "$greeter" }, "\(variables.map(\.label))")
        #expect(greeter.insertText == "$greeter")
        #expect(!variables.contains { $0.kind == .snippet })
        let members = await items(after: "$greeter->")
        #expect(members.contains { $0.label == "greet" }, "\(members.map(\.label))")
        #expect(!members.contains { $0.kind == .snippet })  // no snippets after ->
        let snippets = await items(after: "fore")
        #expect(snippets.contains { $0.label == "foreach" && $0.kind == .snippet })
        await workspace.shutdown()
    }
}

/// Features Intelephense keeps behind its licence, exercised through Phpactor (free).
/// Runs when `phpactor` is on the search path (e.g. ~/.local/bin/phpactor from phpactor.phar).
@MainActor
@Suite(.serialized) struct WorkspacePhpactorTests {
    nonisolated static let available = PHPIDECore.ToolLocator.find("phpactor") != nil && PHPIDECore.ToolLocator.find("composer") != nil

    private func open(_ files: [String: String]) async throws -> (Workspace, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-phpactor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base.appendingPathComponent("src"), withIntermediateDirectories: true)
        let dir = base.canonicalFileURL
        try #"{"autoload": {"psr-4": {"App\\": "src/"}}}"#.write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
        for (path, text) in files { try text.write(to: dir.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        // Phpactor finds classes through Composer's autoloader.
        if let composer = PHPIDECore.ToolLocator.find("composer") {
            _ = await ProcessRunner.run(composer, ["dump-autoload", "--no-interaction"], in: dir)
        }
        let workspace = Workspace()
        workspace.preferredLanguageServer = .phpactor
        await workspace.openFolder(dir)
        #expect(workspace.lspStatus.hasPrefix("phpactor"), "\(workspace.lspStatus)")
        return (workspace, dir)
    }

    @Test(.enabled(if: available), .timeLimit(.minutes(1)))
    func renamesAcrossOpenAndClosedFiles() async throws {
        let (workspace, dir) = try await open([
            "index.php": "<?php\n\nuse App\\Greeter;\n\n(new Greeter())->greet();\n",
            "src/Greeter.php": "<?php\n\nnamespace App;\n\nclass Greeter\n{\n    public function greet(): void {}\n}\n",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let main = try #require(workspace.activeDocument)
        let offset = (main.text as NSString).range(of: "greet()").location + 1
        // Rename only reaches files Phpactor has indexed: wait until it sees both the declaration and the call.
        for _ in 0..<40 {
            await workspace.findReferences(in: main, at: offset)
            if workspace.referenceResults.count == 2 { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        #expect(workspace.referenceResults.count == 2, "\(workspace.referenceTitle)")
        #expect(await workspace.prepareRename(in: main, at: offset) == "greet")
        // Right after start-up Phpactor may still be creating its index: retry until it answers.
        var error: String? = "not tried"
        for _ in 0..<20 where error != nil {
            error = await workspace.renameSymbol(in: main, at: offset, to: "salute")
            if error != nil { try await Task.sleep(for: .milliseconds(500)) }
        }
        #expect(error == nil)
        #expect(main.text.contains("->salute()") && main.isDirty)  // open: buffer
        let greeter = try String(contentsOf: dir.appendingPathComponent("src/Greeter.php"), encoding: .utf8)
        #expect(greeter.contains("function salute()"))  // closed: disk
        await workspace.shutdown()
    }

    @Test(.enabled(if: available), .timeLimit(.minutes(1)))
    func findsImplementations() async throws {
        let (workspace, dir) = try await open([
            "index.php": "<?php\n\nuse App\\Shape;\n\nfunction area(Shape $s): float { return $s->area(); }\n",
            "src/Shape.php": "<?php\n\nnamespace App;\n\ninterface Shape\n{\n    public function area(): float;\n}\n",
            "src/Square.php": "<?php\n\nnamespace App;\n\nclass Square implements Shape\n{\n    public function area(): float { return 4.0; }\n}\n",
            "src/Circle.php": "<?php\n\nnamespace App;\n\nclass Circle implements Shape\n{\n    public function area(): float { return 3.14; }\n}\n",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let main = try #require(workspace.activeDocument)
        // Implementations come from Phpactor's background index: ask again until it has caught up.
        for _ in 0..<20 {
            await workspace.jumpToImplementation(from: main, at: (main.text as NSString).range(of: "Shape $s").location + 1)
            if workspace.referenceTitle.hasPrefix("2 ") { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        #expect(workspace.referenceTitle == "2 implementations of ‘Shape’", "\(workspace.referenceTitle)")
        await workspace.shutdown()
    }

    @Test(.enabled(if: available), .timeLimit(.minutes(1)))
    func offersCodeActions() async throws {
        let (workspace, dir) = try await open([
            "index.php": "<?php\n\n$g = new Greeter();\n",
            "src/Greeter.php": "<?php\n\nnamespace App;\n\nclass Greeter {}\n",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let main = try #require(workspace.activeDocument)
        // "Import class" needs Phpactor's diagnostics and index, which lag on a slow (CI) machine: ask until offered.
        var actions: [CodeAction] = []
        for _ in 0..<60 {
            actions = await workspace.codeActions(in: main, at: (main.text as NSString).range(of: "Greeter").location + 1)
            if actions.contains(where: { $0.title.localizedCaseInsensitiveContains("import") }) { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let importClass = try #require(actions.first { $0.title.localizedCaseInsensitiveContains("import") }, "\(actions.map(\.title))")
        await workspace.perform(importClass)
        for _ in 0..<50 where !main.text.contains("use App\\Greeter;") { try await Task.sleep(for: .milliseconds(100)) }
        #expect(main.text.contains("use App\\Greeter;"))
        await workspace.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceComposerPackagesTests {
    private func waitForCommand(_ workspace: Workspace) async throws {
        for _ in 0..<1200 where workspace.isRunning || !workspace.output.contains("[process exited") {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(100))  // completion handler refreshes the list
    }

    /// Needs network access to Packagist.
    @Test(.enabled(if: PHPIDECore.ToolLocator.find("composer") != nil), .timeLimit(.minutes(2)))
    func requiresListsAndRemovesAPackage() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-packages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.canonicalFileURL
        try #"{"name": "t/t", "require": {"php": ">=8.1"}}"#.write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)

        let workspace = Workspace()
        await workspace.openFolder(dir)
        workspace.showPackages()
        #expect(workspace.isShowingPackages && workspace.packages.map(\.name) == ["php"])

        workspace.requirePackage("psr/log:^3.0", dev: false)
        try await waitForCommand(workspace)
        let log = try #require(workspace.packages.first { $0.name == "psr/log" }, "\(workspace.output)")
        #expect(log.constraint.hasPrefix("^3") && log.installed?.hasPrefix("3.") == true && !log.isDev)

        await workspace.checkOutdatedPackages()
        #expect(!workspace.isCheckingOutdated && workspace.didCheckOutdated)

        workspace.removePackage(log)
        try await waitForCommand(workspace)
        #expect(!workspace.packages.contains { $0.name == "psr/log" })
        await workspace.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceProjectFormatterTests {
    /// The fixture project (PHPIDE_PHPUNIT_PROJECT) has Laravel Pint in vendor/bin.
    @Test(.enabled(if: WorkspacePHPUnitTests.project != nil), .timeLimit(.minutes(1)))
    func formatsWithTheProjectsPint() async throws {
        let dir = URL(fileURLWithPath: try #require(WorkspacePHPUnitTests.project)).canonicalFileURL
        try #require(PHPFormatter.locate(in: dir)?.0 == .pint, "composer install the fixture first")
        let file = dir.appendingPathComponent("format-\(UUID().uuidString.prefix(6)).php")
        try "<?php\nfunction  f( $a ){\nreturn $a;}\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let workspace = Workspace()
        await workspace.openFolder(dir)
        let document = try #require(workspace.openFile(file))
        await workspace.format(document)
        #expect(document.text.contains("function f($a)\n{\n    return $a;\n}"), "\(document.text)")
        #expect(document.isDirty)  // formatted in the buffer, not on disk yet
        #expect(try String(contentsOf: file, encoding: .utf8).contains("function  f( $a )"))
        // No temp files left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".phpide-format-") }
        #expect(leftovers.isEmpty)
        await workspace.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceFrameworkTests {
    /// Tests/Fixtures/console-app after `composer install` (a real Symfony Console app).
    nonisolated static let project = ProcessInfo.processInfo.environment["PHPIDE_CONSOLE_PROJECT"]

    @Test(.enabled(if: project != nil && PHPIDECore.ToolLocator.find("php") != nil), .timeLimit(.minutes(1)))
    func listsAndRunsCommandsAndOpensRouteControllers() async throws {
        let dir = URL(fileURLWithPath: try #require(Self.project)).canonicalFileURL
        let workspace = Workspace()
        await workspace.openFolder(dir)
        #expect(workspace.framework == .symfony)

        await workspace.showConsoleCommands()
        #expect(workspace.isShowingConsoleCommands && workspace.frameworkError == nil)
        #expect(workspace.consoleCommands.contains { $0.name == "app:greet" && $0.description == "Greets someone" })
        #expect(!workspace.consoleCommands.contains { $0.name == "_complete" })
        workspace.isShowingConsoleCommands = false

        workspace.runConsoleCommand("app:greet", arguments: "\"Ada Lovelace\"")
        for _ in 0..<200 where workspace.isRunning || !workspace.output.contains("[process exited") {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(workspace.output.contains("Hello, Ada Lovelace!"))

        await workspace.showRoutes()
        #expect(workspace.routes.map(\.name) == ["app_home", "app_user_show"])
        let show = try #require(workspace.routes.first { $0.name == "app_user_show" })
        #expect(workspace.openController(for: show))
        #expect(workspace.activeDocument?.name == "UserController.php" && !workspace.isShowingRoutes)
        #expect(workspace.activeDocument?.revealTarget?.position.line == 13)  // public function show(
        let home = try #require(workspace.routes.first { $0.name == "app_home" })
        #expect(!workspace.openController(for: home))  // HomeController doesn't exist in the fixture
        await workspace.shutdown()
    }
}

@MainActor
@Suite struct WorkspaceCoverageTests {
    @Test(.enabled(if: WorkspacePHPUnitTests.project != nil), .timeLimit(.minutes(1)))
    func measuresLineCoverageWithXdebug() async throws {
        let dir = URL(fileURLWithPath: try #require(WorkspacePHPUnitTests.project)).canonicalFileURL
        let workspace = Workspace()
        await workspace.openFolder(dir)
        let xdebug = await workspace.refreshXdebugStatus()
        try #require(xdebug.isAvailable, "needs Xdebug")

        workspace.runTestsWithCoverage()
        for _ in 0..<400 where workspace.isRunning || !workspace.output.contains(" skipped — exit ") {
            try await Task.sleep(for: .milliseconds(50))
        }
        let coverage = try #require(workspace.coverage, "\(workspace.output)")
        let greeter = try #require(coverage.files[Workspace.key(for: dir.appendingPathComponent("src/Greeter.php"))])
        #expect(greeter.percent == 100)
        #expect(coverage.files[Workspace.key(for: dir.appendingPathComponent("src/Broken.php"))]?.percent == 0)
        #expect(workspace.testReport.failed >= 1)  // tests still reported alongside coverage

        let document = try #require(workspace.openFile(dir.appendingPathComponent("src/Greeter.php")))
        #expect(workspace.coverageLines(for: document).values.allSatisfy { $0 })
        await workspace.shutdown()
    }
}
