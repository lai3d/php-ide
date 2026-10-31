import Foundation
import Testing
@testable import PHPIDECore

@Suite struct XdebugTests {
    @Test func classifiesPHPAnswers() {
        #expect(Xdebug.status(extensionDirOutput: "\nloaded\n") == .loaded)
        #expect(Xdebug.status(extensionDirOutput: "Warning: x\n/ext\n", fileExists: { $0 == "/ext/xdebug.so" }) == .installed(path: "/ext/xdebug.so"))
        #expect(Xdebug.status(extensionDirOutput: "\n/ext\n", fileExists: { _ in false }) == .missing)
        #expect(Xdebug.status(extensionDirOutput: "", fileExists: { _ in true }) == .missing)
    }

    @Test func runtimeArgumentsLoadTheExtensionOnlyWhenNeeded() {
        #expect(XdebugStatus.installed(path: "/e/xdebug.so").runtimeArguments
                == ["-dzend_extension=/e/xdebug.so", "-dxdebug.mode=debug", "-dxdebug.start_with_request=yes"])
        #expect(XdebugStatus.loaded.runtimeArguments == ["-dxdebug.mode=debug", "-dxdebug.start_with_request=yes"])
        #expect(XdebugStatus.missing.runtimeArguments.isEmpty)
    }

    @Test(.enabled(if: ToolLocator.find("php") != nil))
    func asksTheRealPHP() async throws {
        let status = await Xdebug.status(php: try #require(ToolLocator.find("php")))
        #expect(status == .loaded || status == .missing || { if case .installed = status { return true }; return false }())
    }
}
