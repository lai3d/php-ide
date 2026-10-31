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
