import Foundation
import Testing
@testable import PHPIDECore

@Suite struct PHPLanguageServerTests {
    let bin = URL(fileURLWithPath: "/opt/bin")

    @Test func prefersIntelephenseThenFallsBack() {
        let both = { (name: String) -> URL? in self.bin.appendingPathComponent(name) }
        #expect(PHPLanguageServer.locate(preferred: .intelephense, find: both)?.arguments == ["--stdio"])
        #expect(PHPLanguageServer.locate(preferred: .phpactor, find: both)?.arguments == ["language-server"])

        let onlyPhpactor = { (name: String) -> URL? in name == "phpactor" ? self.bin.appendingPathComponent(name) : nil }
        #expect(PHPLanguageServer.locate(preferred: .intelephense, find: onlyPhpactor)?.kind == .phpactor)
        #expect(PHPLanguageServer.locate(preferred: .intelephense, find: { _ in nil }) == nil)
    }

    @Test func recognizesPHPFiles() {
        #expect(PHPLanguageServer.isPHPFile(URL(fileURLWithPath: "/a/index.php")))
        #expect(PHPLanguageServer.isPHPFile(URL(fileURLWithPath: "/a/view.PHTML")))
        #expect(!PHPLanguageServer.isPHPFile(URL(fileURLWithPath: "/a/app.js")))
        #expect(PHPLanguageServer.isWatched(path: "/a/composer.json"))
        #expect(!PHPLanguageServer.isWatched(path: "/a/README.md"))
    }

    @Test func licenceKeyOnlyWhenSet() {
        #expect(PHPLanguageServer.initializationOptions(for: .intelephense)["licenceKey"] == nil)
        #expect(PHPLanguageServer.initializationOptions(for: .intelephense, licenceKey: " K ")["licenceKey"]?.stringValue == "K")
        #expect(PHPLanguageServer.initializationOptions(for: .intelephense)["storagePath"]?.stringValue?.hasSuffix("PHPIDE/intelephense/workspace") == true)
    }
}
