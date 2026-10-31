import Foundation
import Testing
@testable import PHPIDECore

@Suite struct PHPUnitTests {
    static let stream = """
        PHPUnit 11.5.57 by Sebastian Bergmann and contributors.
        ##teamcity[testCount count='5' flowId='1']
        ##teamcity[testSuiteStarted name='CLI Arguments' flowId='1']
        ##teamcity[testSuiteStarted name='Hello\\Tests\\GreeterTest' locationHint='php_qn:///p/tests/GreeterTest.php::\\Hello\\Tests\\GreeterTest' flowId='1']
        ##teamcity[testStarted name='testGreet' locationHint='php_qn:///p/tests/GreeterTest.php::\\Hello\\Tests\\GreeterTest::testGreet' flowId='1']
        ##teamcity[testFinished name='testGreet' duration='5' flowId='1']
        ##teamcity[testSuiteFinished name='Hello\\Tests\\GreeterTest' flowId='1']
        ##teamcity[testSuiteStarted name='Hello\\Tests\\MoreTest' locationHint='php_qn:///p/tests/MoreTest.php::\\Hello\\Tests\\MoreTest' flowId='1']
        ##teamcity[testStarted name='fails' locationHint='php_qn:///p/tests/MoreTest.php::\\Hello\\Tests\\MoreTest::fails' flowId='1']
        ##teamcity[testFailed name='fails' message='numbers differ|nFailed asserting that 2 is identical to 1.' details='/p/tests/MoreTest.php:10|n' duration='7' flowId='1']
        printed
        ##teamcity[testFinished name='fails' duration='7' flowId='1']
        ##teamcity[testStarted name='testSkipped' locationHint='php_qn:///p/tests/MoreTest.php::\\Hello\\Tests\\MoreTest::testSkipped' flowId='1']
        ##teamcity[testIgnored name='testSkipped' message='later' duration='0' flowId='1']
        ##teamcity[testFinished name='testSkipped' duration='1' flowId='1']
        ##teamcity[testSuiteStarted name='testAdd' locationHint='php_qn:///p/tests/MoreTest.php::\\Hello\\Tests\\MoreTest::testAdd' flowId='1']
        ##teamcity[testStarted name='testAdd with data set "same"' locationHint='php_qn:///p/tests/MoreTest.php::\\Hello\\Tests\\MoreTest::testAdd with data set "same"' flowId='1']
        ##teamcity[testFinished name='testAdd with data set "same"' duration='0' flowId='1']
        ##teamcity[testStarted name='testAdd with data set "diff"' locationHint='php_qn:///p/tests/MoreTest.php::\\Hello\\Tests\\MoreTest::testAdd with data set "diff"' flowId='1']
        ##teamcity[testFailed name='testAdd with data set "diff"' message='It|'s |[bad|]' details='' duration='0' flowId='1']
        ##teamcity[testFinished name='testAdd with data set "diff"' duration='1' flowId='1']
        ##teamcity[testSuiteFinished name='testAdd' flowId='1']
        ##teamcity[testSuiteFinished name='Hello\\Tests\\MoreTest' flowId='1']
        FAILURES!
        """

    @Test func aggregatesATeamCityStream() throws {
        var report = TestReport()
        Self.stream.split(separator: "\n").forEach { report.consume(line: String($0)) }
        #expect(report.tests.map(\.name) == ["testGreet", "fails", "testSkipped", "testAdd", "testAdd/same", "testAdd/diff"])
        #expect(report.tests.map(\.status) == [.passed, .failed, .skipped, .failed, .passed, .failed])
        #expect((report.passed, report.failed, report.skipped) == (2, 2, 1))  // the testAdd group row isn't counted
        let fails = report.tests[1]
        #expect(fails.className == "Hello\\Tests\\MoreTest" && fails.file == "/p/tests/MoreTest.php")
        #expect(fails.output == "numbers differ\nFailed asserting that 2 is identical to 1.\n/p/tests/MoreTest.php:10\nprinted\n")
        #expect(fails.elapsed == 0.007)
        #expect(report.tests[5].output == "It's [bad]\n" && report.tests[5].depth == 1 && report.tests[5].shortName == "diff")
        #expect(report.buildOutput.contains("PHPUnit 11.5.57") && report.buildOutput.contains("FAILURES!"))
    }

    @Test func findsTestMethods() {
        let source = """
            <?php
            namespace App\\Tests;
            final class FooTest extends TestCase
            {
                public function testOne(): void {}
                #[Test]
                public function two(): void {}
                /**
                 * @test
                 */
                public function three(): void {}
                #[DataProvider('cases')]
                public function testFour(int $a): void {}
                public static function cases(): array { return []; }
                private function testHelper(): void {}
                public function helper(): void {}
            }
            """
        #expect(PHPTestFinder.testMethods(in: source).map(\.name) == ["testOne", "two", "three", "testFour"])
        #expect(PHPTestFinder.testMethods(in: source).first?.line == 4)
        let ns = source as NSString
        #expect(PHPTestFinder.enclosingTest(in: source, at: ns.range(of: "two(): void {}").location + 12) == "two")
        #expect(PHPTestFinder.enclosingTest(in: source, at: ns.range(of: "return []").location) == nil)
        #expect(PHPTestFinder.className(in: source) == "App\\Tests\\FooTest")
        #expect(PHPTestFinder.isTestFile("FooTest.php") && !PHPTestFinder.isTestFile("Foo.php"))
    }

    @Test func buildsRunnerArguments() {
        let root = URL(fileURLWithPath: "/nonexistent")
        #expect(PHPTestRunner.arguments(root: root, file: "tests/A.php") == ["--teamcity", "tests/A.php"])
        #expect(PHPTestRunner.arguments(root: root, file: "t.php", className: "App\\FooTest", method: "testOne")
                == ["--teamcity", "--filter", "/App\\\\FooTest::testOne( with data set .*)?$/", "t.php"])
    }
}
