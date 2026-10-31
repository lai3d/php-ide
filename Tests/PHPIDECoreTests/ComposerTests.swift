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
