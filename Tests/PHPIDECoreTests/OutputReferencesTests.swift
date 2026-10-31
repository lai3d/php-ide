import Foundation
import Testing
@testable import PHPIDECore

@Suite struct OutputReferencesTests {
    private func refs(_ line: String) -> [String] {
        OutputReferences.fileReferences(in: line).map { "\($0.file)#\($0.line)" }
    }

    @Test func recognizesPHPStyles() {
        #expect(refs("PHP Parse error:  syntax error, unexpected end of file in /tmp/a b/x.php on line 7") == ["b/x.php#7"])
        #expect(refs("PHP Parse error:  unexpected token in /srv/app/src/Foo.php on line 12") == ["/srv/app/src/Foo.php#12"])
        #expect(refs("/home/u/app/tests/GreeterTest.php:21") == ["/home/u/app/tests/GreeterTest.php#21"])
        #expect(refs("#0 src/Kernel.php(88): App\\Kernel->boot()") == ["src/Kernel.php#88"])
        #expect(refs("Error at index.php, line 3") == ["index.php#3"])
        #expect(refs("plain text, no file here.php") == [])
    }
}
