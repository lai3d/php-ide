import Foundation
import Testing
@testable import PHPIDECore

@Suite struct ComposerTests {
    @Test func listsScriptsCustomFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-composer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(Composer.scripts(in: dir).isEmpty)
        try #"{"scripts": {"test": "phpunit", "post-install-cmd": ["@php -v"], "analyse": "phpstan", "lint:fix": "pint"}}"#
            .write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
        #expect(Composer.scripts(in: dir) == ["analyse", "lint:fix", "test", "post-install-cmd"])
    }
}

@Suite struct ComposerPackageTests {
    @Test func readsDependenciesWithLockedVersions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("phpide-pkgs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"require": {"php": ">=8.2", "monolog/monolog": "^3.0", "ext-json": "*"}, "require-dev": {"phpunit/phpunit": "^11.0"}}"#
            .write(to: dir.appendingPathComponent("composer.json"), atomically: true, encoding: .utf8)
        try #"{"packages": [{"name": "monolog/monolog", "version": "3.7.0"}], "packages-dev": [{"name": "phpunit/phpunit", "version": "11.5.57"}]}"#
            .write(to: dir.appendingPathComponent("composer.lock"), atomically: true, encoding: .utf8)
        let packages = Composer.packages(in: dir)
        #expect(packages.map(\.name) == ["ext-json", "php", "monolog/monolog", "phpunit/phpunit"])
        #expect(packages.map(\.isDev) == [false, false, false, true])
        #expect(packages[2].installed == "3.7.0" && packages[3].installed == "11.5.57" && packages[1].installed == nil)
        #expect(packages[0].isPlatform && packages[1].isPlatform && !packages[2].isPlatform)
    }

    @Test func parsesOutdatedJSONAfterWarnings() {
        let output = """
            Warning: something on stderr
            {"installed": [{"name": "phpunit/phpunit", "version": "11.5.57", "latest": "13.4.1", "latest-status": "update-possible"}]}
            """
        let outdated = Composer.parseOutdated(output)
        #expect(outdated["phpunit/phpunit"]?.latest == "13.4.1" && outdated["phpunit/phpunit"]?.status == "update-possible")
        #expect(Composer.parseOutdated("nope").isEmpty)
    }

    @Test func validatesPackageNames() {
        #expect(Composer.isValidPackageName("monolog/monolog") && Composer.isValidPackageName("symfony/http-foundation"))
        #expect(!Composer.isValidPackageName("Monolog") && !Composer.isValidPackageName("a/b c") && !Composer.isValidPackageName("x"))
    }
}
