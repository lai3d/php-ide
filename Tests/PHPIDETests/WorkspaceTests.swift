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
        #expect(SessionStore.recentProjects.first?.path == dir.path)
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
