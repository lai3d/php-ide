import Foundation
import Testing
@testable import PHPIDECore

@Suite struct CoverageTests {
    static let clover = """
        <?xml version="1.0" encoding="UTF-8"?>
        <coverage generated="1793485055">
          <project timestamp="1793485055" name="Clover Coverage">
            <file name="/p/src/Broken.php">
              <line num="10" type="stmt" count="0"/>
              <metrics loc="12" ncloc="11" statements="1" coveredstatements="0"/>
            </file>
            <package name="Hello">
              <file name="/p/src/Greeter.php">
                <class name="Hello\\Greeter" namespace="Hello"><metrics statements="3" coveredstatements="2"/></class>
                <line num="9" type="method" name="__construct" visibility="public" complexity="1" crap="1" count="1"/>
                <line num="13" type="stmt" count="4"/>
                <line num="14" type="stmt" count="0"/>
                <line num="15" type="stmt" count="1"/>
              </file>
            </package>
          </project>
        </coverage>
        """

    @Test func parsesCloverReports() throws {
        let report = CoverageReport.parseClover(Data(Self.clover.utf8)) { "/real" + $0 }
        let greeter = try #require(report.files["/real/p/src/Greeter.php"])
        #expect(greeter.statements == 3 && greeter.coveredStatements == 2)
        #expect(greeter.lines == [12: true, 13: false, 14: true])  // zero-based; the method line isn't a statement
        #expect(report.files["/real/p/src/Broken.php"]?.percent == 0)
        #expect(Int(report.percent) == 50)  // 2 of 4 statements
    }

    @Test func toleratesBrokenXML() {
        #expect(CoverageReport.parseClover(Data("<coverage><file name=\"/a.php\"><line num=".utf8)).files.count <= 1)
    }
}
