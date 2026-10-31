import Foundation
import Testing
@testable import PHPIDECore

@Suite struct PHPHighlighterTests {
    private func kinds(_ source: String) -> [(String, SyntaxTokenKind)] {
        let ns = source as NSString
        return PHPHighlighter.tokenize(source).map { (ns.substring(with: $0.range), $0.kind) }
    }

    @Test func classifiesTokens() {
        let tokens = kinds(#"<?php function greet(string $name): ?int { return strlen("hi // no") + 42; } // done"#)
        #expect(tokens.map(\.0) == ["<?php", "function", "greet", "string", "$name", "int", "return", "strlen",
                                    #""hi // no""#, "42", "// done"])
        #expect(tokens.map(\.1) == [.phpTag, .keyword, .function, .type, .variable, .type, .keyword, .function,
                                    .string, .number, .comment])
    }

    @Test func inlineHTMLIsLeftAlone() {
        let tokens = kinds("<h1 class=\"x\"><?= $title ?></h1><p>if return</p>")
        #expect(tokens.map(\.0) == ["<?=", "$title", "?>"])
        #expect(tokens.map(\.1) == [.phpTag, .variable, .phpTag])
    }

    @Test func lineCommentsEndAtCloseTag() {
        #expect(kinds("<?php # note ?>text").map(\.0) == ["<?php", "# note ", "?>"])
    }

    @Test func interpolatesDoubleQuotedStringsOnly() {
        let tokens = kinds(#"<?php "Hi $user->name {$a['b']}"; 'no $x';"#)
        #expect(tokens.map(\.1) == [.phpTag, .string, .variable, .variable, .string])
        #expect(tokens.map(\.0)[2...3] == ["$user->name", "{$a['b']}"])
    }

    @Test func heredocAndNowdoc() {
        let source = "<?php\n$a = <<<EOT\n  Hello $name\n  if\n  EOT;\n$b = <<<'RAW'\n$kept\nRAW;\necho 1;"
        let tokens = kinds(source)
        #expect(tokens.map(\.1) == [.phpTag, .variable, .string, .variable, .variable, .string, .keyword, .number])
        #expect(tokens[2].0 == "<<<EOT\n  Hello $name\n  if\n  EOT")
        #expect(tokens[5].0 == "<<<'RAW'\n$kept\nRAW")
    }

    @Test func classNamesAttributesAndStatics() {
        let tokens = kinds("<?php #[Route('/x')] final class A extends \\Base\\Ctrl { } new Foo(); Bar::baz(); Bar::MAX; $this->go();")
        let named = Dictionary(tokens.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        #expect(named["#["] == .attribute && named["Route"] == .attribute)
        #expect(named["'/x'"] == .string)
        #expect(named["A"] == .type && named["Base"] == .type && named["Ctrl"] == .type && named["Foo"] == .type)
        #expect(named["Bar"] == .type && named["baz"] == .function && named["MAX"] == .builtin)
        #expect(named["$this"] == .builtin && named["go"] == .function)
    }

    @Test func keywordsAreCaseInsensitiveAndConstantsBuiltin() {
        let tokens = kinds("<?php IF (TRUE) { Echo NULL; } __DIR__;")
        #expect(tokens.map(\.1) == [.phpTag, .keyword, .builtin, .keyword, .builtin, .builtin])
    }

    @Test func docCommentTags() {
        let tokens = kinds("<?php /** Greets.\n * @param string $n\n * @return void email@x.io */")
        #expect(tokens.filter { $0.1 == .docTag }.map(\.0) == ["@param", "@return"])
    }

    @Test func numbers() {
        #expect(kinds("<?php 0x1F 0b101 1_000 3.14 .5 1e-3").dropFirst().map(\.0) == ["0x1F", "0b101", "1_000", "3.14", ".5", "1e-3"])
    }

    @Test func unterminatedConstructsRunToTheEnd() {
        #expect(kinds("<?php /* open").last?.1 == .comment)
        #expect(kinds("<?php 'open").last?.1 == .string)
        #expect(kinds("<?php $x = <<<EOT\nno end").last?.0 == "<<<EOT\nno end")
    }
}
