import Foundation
import Testing
@testable import PHPIDECore

@Suite struct RunConfigurationTests {
    @Test func splitsShellWords() {
        #expect(ShellWords.split(#"-port 8080 --name "my app" 'a b' c\ d"#) == ["-port", "8080", "--name", "my app", "a b", "c d"])
        #expect(ShellWords.split("   ").isEmpty)
        #expect(ShellWords.split(#"--flag="" x"#) == ["--flag=", "x"])
    }

    @Test func parsesEnvironment() {
        let config = RunConfiguration(name: "server", script: "bin/server.php", arguments: "-v",
                                      environment: "PORT=8080\n# comment\nDSN=postgres://u@h/db?x=1\n\n")
        #expect(config.environmentVariables == ["PORT": "8080", "DSN": "postgres://u@h/db?x=1"])
    }

    @Test func webServerArgumentsAndURL() {
        let server = RunConfiguration.server(name: "web", documentRoot: "public", port: 8080, router: "public/index.php")
        #expect(server.phpArguments == ["-S", "127.0.0.1:8080", "-t", "public", "public/index.php"])
        #expect(server.url?.absoluteString == "http://127.0.0.1:8080/")
        let script = RunConfiguration(name: "cli", script: "bin/console", arguments: "cache:clear --env=prod")
        #expect(script.phpArguments == ["bin/console", "cache:clear", "--env=prod"] && script.url == nil)
    }

    @Test func decodesConfigurationsSavedBeforeWebServers() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"main","script":"main.php","arguments":"-v","environment":""}"#
        let config = try JSONDecoder().decode(RunConfiguration.self, from: Data(old.utf8))
        #expect(config.kind == .script && config.script == "main.php" && config.port == 8000)
        let roundTrip = try JSONDecoder().decode(RunConfiguration.self, from: JSONEncoder().encode(RunConfiguration.server(name: "w", documentRoot: ".")))
        #expect(roundTrip.kind == .server && roundTrip.documentRoot == ".")
    }

    @Test func findsEntryPoints() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-scripts-\(UUID().uuidString)")
        let fm = FileManager.default
        for dir in ["bin", "public", "src", "vendor/x"] {
            try fm.createDirectory(at: base.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: base) }
        func write(_ path: String, _ text: String = "<?php\n") throws {
            try text.write(to: base.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        try write("worker.php"); try write("index.php"); try write("public/index.php"); try write("src/Lib.php")
        try write("artisan", "#!/usr/bin/env php\n<?php\n"); try write("README.md", "# hi\n")
        try write("bin/console", "#!/usr/bin/env php\n<?php\n"); try write("bin/run.sh", "#!/bin/sh\n")
        try write("vendor/x/index.php")
        #expect(PHPScripts.entryPoints(under: base) == ["index.php", "public/index.php", "artisan", "bin/console", "worker.php"])
    }
}
