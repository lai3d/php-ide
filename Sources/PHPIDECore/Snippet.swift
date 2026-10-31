import Foundation

/// An expanded LSP snippet: plain text plus tab stops (`$1`, `${2:default}`, … then `$0`).
public struct Snippet: Sendable, Hashable {
    public let text: String
    /// UTF-16 ranges in `text`, in visiting order; the last is `$0` (or the end of the text).
    public let stops: [NSRange]

    public init(text: String, stops: [NSRange]) {
        self.text = text
        self.stops = stops
    }

    /// Parses LSP snippet syntax: `$n`, `${n}`, `${n:placeholder}` (nestable), `${n|a,b|}`
    /// (first choice), `$0`, and `\` escapes. Only the first occurrence of a stop is kept.
    public static func parse(_ snippet: String) -> Snippet {
        let chars = Array(snippet)
        var output = ""
        var length = 0  // UTF-16 length of output
        var stops: [Int: NSRange] = [:]
        var i = 0

        func append(_ c: Character) {
            output.append(c)
            length += c.utf16.count
        }

        func readNumber() -> Int? {
            var digits = ""
            while i < chars.count, chars[i].isNumber { digits.append(chars[i]); i += 1 }
            return Int(digits)
        }

        /// Parses until an unescaped "}" at this nesting level (consumed), or the end.
        func parseBody(untilBrace: Bool) {
            while i < chars.count {
                let c = chars[i]
                if c == "\\", i + 1 < chars.count, "$}\\,|".contains(chars[i + 1]) {
                    // Only these are escapable; any other backslash is literal (e.g. "\n" in Go strings).
                    append(chars[i + 1])
                    i += 2
                } else if untilBrace, c == "}" {
                    i += 1
                    return
                } else if c == "$", i + 1 < chars.count, chars[i + 1].isNumber {
                    i += 1
                    if let n = readNumber(), stops[n] == nil { stops[n] = NSRange(location: length, length: 0) }
                } else if c == "$", i + 1 < chars.count, chars[i + 1] == "{" {
                    i += 2
                    guard let n = readNumber() else { append("$"); continue }
                    let start = length
                    if i < chars.count, chars[i] == ":" {
                        i += 1
                        parseBody(untilBrace: true)
                    } else if i < chars.count, chars[i] == "|" {
                        // Choices: keep the first one.
                        i += 1
                        var choice = ""
                        while i < chars.count, chars[i] != "," && chars[i] != "|" { choice.append(chars[i]); i += 1 }
                        while i < chars.count, chars[i] != "}" { i += 1 }
                        i += 1
                        choice.forEach(append)
                    } else if i < chars.count, chars[i] == "}" {
                        i += 1
                    }
                    if stops[n] == nil { stops[n] = NSRange(location: start, length: length - start) }
                } else {
                    append(c)
                    i += 1
                }
            }
        }

        parseBody(untilBrace: false)
        var ordered = stops.filter { $0.key != 0 }.sorted { $0.key < $1.key }.map(\.value)
        ordered.append(stops[0] ?? NSRange(location: length, length: 0))
        return Snippet(text: output, stops: ordered)
    }

    /// Indents every line after the first (for insertion at an indented caret).
    public func indented(_ indent: String) -> Snippet {
        guard !indent.isEmpty, text.contains("\n") else { return self }
        let ns = text as NSString
        let extra = (indent as NSString).length
        var newlines: [Int] = []
        for i in 0..<ns.length where ns.character(at: i) == 0x0A { newlines.append(i) }
        let shifted = stops.map { stop -> NSRange in
            let before = newlines.filter { $0 < stop.location }.count
            let inside = newlines.filter { $0 >= stop.location && $0 < NSMaxRange(stop) }.count
            return NSRange(location: stop.location + before * extra, length: stop.length + inside * extra)
        }
        return Snippet(text: text.replacingOccurrences(of: "\n", with: "\n" + indent), stops: shifted)
    }
}

/// Built-in PHP snippets, offered in completion by trigger word. Bodies indent with `\t`
/// (expanded to `TextEditing.indentUnit`); `\$` is a literal dollar.
public enum PHPSnippets {
    public static let all: [(trigger: String, detail: String, body: String)] = [
        ("class", "final class Name { … }", "final class ${1:Name}\n{\n\t$0\n}"),
        ("interface", "interface Name { … }", "interface ${1:Name}\n{\n\t$0\n}"),
        ("enum", "enum Name: string { case … }", "enum ${1:Name}: ${2:string}\n{\n\tcase ${3:Value} = '${4:value}';$0\n}"),
        ("ctor", "public function __construct(…) {}", "public function __construct(\n\tprivate readonly ${1:Type} \\$${2:name},\n) {\n}$0"),
        ("pubf", "public function name(): type { … }", "public function ${1:name}(${2}): ${3:void}\n{\n\t$0\n}"),
        ("prif", "private function name(): type { … }", "private function ${1:name}(${2}): ${3:void}\n{\n\t$0\n}"),
        ("pubsf", "public static function name(): type { … }", "public static function ${1:name}(${2}): ${3:void}\n{\n\t$0\n}"),
        ("fn", "fn(…) => …", "fn(${1:\\$x}) => ${2:\\$x}$0"),
        ("func", "function (…) use (…) { … }", "function (${1}) use (${2}) {\n\t$0\n}"),
        ("foreach", "foreach (… as $k => $v) { … }", "foreach (\\$${1:items} as \\$${2:key} => \\$${3:value}) {\n\t$0\n}"),
        ("fore", "foreach (… as $v) { … }", "foreach (\\$${1:items} as \\$${2:item}) {\n\t$0\n}"),
        ("fori", "for ($i = 0; $i < n; $i++) { … }", "for (\\$${1:i} = 0; \\$${1:i} < ${2:\\$count}; \\$${1:i}++) {\n\t$0\n}"),
        ("if", "if (…) { … }", "if (${1:condition}) {\n\t$0\n}"),
        ("ife", "if (…) { … } else { … }", "if (${1:condition}) {\n\t$2\n} else {\n\t$0\n}"),
        ("match", "match (…) { … }", "match (${1:\\$value}) {\n\t${2:'a'} => ${3:1},\n\tdefault => ${4:null},\n}$0"),
        ("try", "try { … } catch (…) { … }", "try {\n\t$1\n} catch (${2:\\\\Throwable} \\$${3:e}) {\n\t$0\n}"),
        ("throw", "throw new …Exception(…)", "throw new ${1:\\\\RuntimeException}('${2:message}');$0"),
        ("test", "public function testName(): void { … }", "public function test${1:Name}(): void\n{\n\t$0\n}"),
        ("testcase", "final class NameTest extends TestCase { … }",
         "use PHPUnit\\\\Framework\\\\TestCase;\n\nfinal class ${1:Name}Test extends TestCase\n{\n\tpublic function test${2:Something}(): void\n\t{\n\t\t$0\n\t}\n}"),
        ("dp", "#[DataProvider] + provider method", "#[\\\\PHPUnit\\\\Framework\\\\Attributes\\\\DataProvider('${1:cases}')]\npublic function test${2:Name}(${3:int} \\$${4:input}): void\n{\n\t$0\n}\n\npublic static function ${1:cases}(): array\n{\n\treturn [\n\t\t'${5:case}' => [${6:1}],\n\t];\n}"),
        ("strict", "declare(strict_types=1);", "declare(strict_types=1);\n$0"),
        ("ns", "namespace …;", "namespace ${1:App};\n$0"),
        ("vd", "var_dump(…);", "var_dump(${1:\\$value});$0"),
        ("dd", "var_dump(…); exit;", "var_dump(${1:\\$value});\nexit(1);$0"),
    ]

    /// Completion items for snippets whose trigger matches `prefix` (fuzzy, needs ≥ 2 chars).
    public static func completions(matching prefix: String) -> [CompletionItem] {
        guard prefix.count >= 2 else { return [] }
        return all.filter { FuzzyMatch.matches(prefix, $0.trigger) }.map {
            let body = $0.body.replacingOccurrences(of: "\t", with: TextEditing.indentUnit)
            return CompletionItem(label: $0.trigger, kind: .snippet, detail: $0.detail,
                                  insertText: Snippet.parse(body).text, sortText: "~" + $0.trigger, snippet: body)
        }
    }
}
