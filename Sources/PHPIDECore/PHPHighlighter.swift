import Foundation

public enum SyntaxTokenKind: Sendable, Hashable {
    case keyword, type, builtin, function, string, comment, number
    /// `$name` (also inside interpolated strings and heredocs).
    case variable
    /// `#[Attribute]`.
    case attribute
    /// `<?php`, `<?=`, `?>`.
    case phpTag
    /// `@param`, `@return`, … inside `/** … */`.
    case docTag
    /// HTML `<tag` / `</tag>` / `>`.
    case tag
    /// HTML attribute names.
    case attributeName
}

public struct SyntaxToken: Sendable, Hashable {
    public let range: NSRange
    public let kind: SyntaxTokenKind

    public init(range: NSRange, kind: SyntaxTokenKind) {
        self.range = range
        self.kind = kind
    }
}

/// A fast hand-written PHP lexer for syntax highlighting. Text outside `<?php … ?>` is lexed as
/// HTML (tags, attributes, comments, and strings / comments inside `<script>` / `<style>`).
/// Later tokens may overlap earlier ones (variables inside strings, tags inside doc comments)
/// and are meant to be painted on top.
public enum PHPHighlighter {
    /// Matched case-insensitively, like PHP itself.
    public static let keywords: Set<String> = [
        "abstract", "and", "as", "break", "callable", "case", "catch", "class", "clone", "const",
        "continue", "declare", "default", "do", "echo", "else", "elseif", "empty", "enddeclare", "endfor",
        "endforeach", "endif", "endswitch", "endwhile", "enum", "eval", "exit", "die", "extends", "final",
        "finally", "fn", "for", "foreach", "function", "global", "goto", "if", "implements", "include",
        "include_once", "instanceof", "insteadof", "interface", "isset", "list", "match", "namespace", "new",
        "or", "print", "private", "protected", "public", "readonly", "require", "require_once", "return",
        "static", "switch", "throw", "trait", "try", "unset", "use", "var", "while", "xor", "yield",
        "self", "parent",
    ]

    public static let types: Set<String> = [
        "int", "integer", "float", "double", "string", "bool", "boolean", "array", "object", "mixed",
        "void", "never", "iterable", "binary",
    ]

    public static let builtins: Set<String> = [
        "true", "false", "null",
        "__class__", "__dir__", "__file__", "__function__", "__line__", "__method__", "__namespace__",
        "__trait__", "__compiler_halt_offset__",
    ]

    /// Words after which the next identifier names a class.
    private static let typeIntroducers: Set<String> = [
        "new", "extends", "implements", "instanceof", "class", "interface", "trait", "enum", "insteadof",
    ]

    public static func tokenize(_ text: String) -> [SyntaxToken] {
        var lexer = Lexer(Array(text.utf16))
        lexer.run()
        return lexer.tokens
    }

    static let jsKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do",
        "else", "export", "extends", "false", "finally", "for", "from", "function", "if", "import", "in",
        "instanceof", "let", "new", "null", "of", "return", "static", "super", "switch", "this", "throw",
        "true", "try", "typeof", "undefined", "var", "void", "while", "yield",
    ]

    private enum HTMLState: Equatable {
        case text, inTag, attributeValue(quote: UInt16), comment, script, style
    }

    private struct Lexer {
        let s: [UInt16]
        var i = 0
        var tokens: [SyntaxToken] = []
        /// Where HTML scanning is, kept across `<?php … ?>` islands (e.g. inside an attribute value).
        private var htmlState = HTMLState.text
        /// Start of a multi-part HTML token (attribute value, comment) that a PHP island interrupted.
        private var segmentStart = 0
        /// The element whose tag is open (lowercased) and whether it's a closing tag.
        private var tagName = ""
        private var tagClosing = false
        /// The last keyword-ish word seen, for "the identifier after `new` is a class".
        var previousWord = ""

        init(_ s: [UInt16]) { self.s = s }

        func at(_ k: Int) -> UInt16 { k < s.count ? s[k] : 0 }
        func starts(_ literal: String, at k: Int, caseInsensitive: Bool = false) -> Bool {
            var k = k
            for c in literal.utf16 {
                guard k < s.count else { return false }
                let d = s[k]
                if d != c && !(caseInsensitive && lower(d) == lower(c)) { return false }
                k += 1
            }
            return true
        }
        func lower(_ c: UInt16) -> UInt16 { (c >= 65 && c <= 90) ? c + 32 : c }
        static func isIdentStart(_ c: UInt16) -> Bool {
            (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 0x80
        }
        static func isIdent(_ c: UInt16) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) }
        static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
        static func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }

        mutating func add(_ start: Int, _ end: Int, _ kind: SyntaxTokenKind) {
            guard end > start else { return }
            tokens.append(SyntaxToken(range: NSRange(location: start, length: end - start), kind: kind))
        }

        mutating func run() {
            while i < s.count {
                html()
                php()
            }
        }

        /// Inline HTML up to the next open tag.
        mutating func html() {
            segmentStart = i
            while i < s.count {
                if at(i) == 60, at(i + 1) == 63 {  // <?  — a PHP island, even mid-attribute
                    flushSegment(upTo: i)
                    let start = i
                    if starts("<?php", at: i, caseInsensitive: true) { i += 5 }
                    else if at(i + 2) == 61 { i += 3 }  // <?=
                    else { i += 2 }
                    add(start, i, .phpTag)
                    return
                }
                switch htmlState {
                case .text: htmlText()
                case .inTag: htmlInTag()
                case .attributeValue(let quote):
                    if s[i] == quote {
                        add(segmentStart, i + 1, .string)
                        i += 1
                        htmlState = .inTag
                    } else {
                        i += 1
                    }
                case .comment:
                    if starts("-->", at: i) {
                        add(segmentStart, i + 3, .comment)
                        i += 3
                        htmlState = .text
                    } else {
                        i += 1
                    }
                case .script, .style:
                    if at(i) == 60, at(i + 1) == 47,
                       starts(htmlState == .script ? "</script" : "</style", at: i, caseInsensitive: true) {
                        htmlState = .text
                    } else {
                        embedded(script: htmlState == .script)
                    }
                }
            }
            flushSegment(upTo: i)
        }

        /// Colors the part of an attribute value / comment seen so far (before a PHP island or the end).
        private mutating func flushSegment(upTo end: Int) {
            switch htmlState {
            case .attributeValue: add(segmentStart, end, .string)
            case .comment: add(segmentStart, end, .comment)
            default: break
            }
        }

        private mutating func htmlText() {
            if starts("<!--", at: i) {
                htmlState = .comment
                segmentStart = i
                i += 4
            } else if s[i] == 60, at(i + 1) == 33, Self.isTagStart(at(i + 2)) {  // <!DOCTYPE …>
                let start = i
                while i < s.count, s[i] != 62, !(s[i] == 60 && at(i + 1) == 63) { i += 1 }
                if at(i) == 62 { i += 1 }
                add(start, i, .tag)
            } else if s[i] == 60, Self.isTagStart(at(i + 1)) || (at(i + 1) == 47 && Self.isTagStart(at(i + 2))) {
                let start = i
                let closing = at(i + 1) == 47
                i += closing ? 2 : 1
                let nameStart = i
                while Self.isTagName(at(i)) { i += 1 }
                add(start, i, .tag)
                tagName = String(decoding: s[nameStart..<i], as: UTF16.self).lowercased()
                tagClosing = closing
                htmlState = .inTag
            } else {
                i += 1
            }
        }

        private mutating func htmlInTag() {
            let c = s[i]
            if c == 62 {  // >
                add(i, i + 1, .tag)
                i += 1
                htmlState = tagClosing ? .text : tagName == "script" ? .script : tagName == "style" ? .style : .text
            } else if c == 47, at(i + 1) == 62 {  // />
                add(i, i + 2, .tag)
                i += 2
                htmlState = .text
            } else if c == 34 || c == 39 {  // "…" or '…'
                htmlState = .attributeValue(quote: c)
                segmentStart = i
                i += 1
            } else if Self.isTagStart(c) || c == 64 || c == 58 {  // name, @click, :bind
                let start = i
                while Self.isTagName(at(i)) || at(i) == 64 || at(i) == 58 || at(i) == 46 { i += 1 }
                add(start, i, .attributeName)
            } else {
                i += 1
            }
        }

        /// One token of JavaScript / CSS inside `<script>` / `<style>`: strings, comments, numbers, JS keywords.
        private mutating func embedded(script: Bool) {
            let c = s[i]
            func stop(_ k: Int) -> Bool { k >= s.count || (s[k] == 60 && (at(k + 1) == 63 || at(k + 1) == 47)) }
            if c == 47, at(i + 1) == 42 {  // /* */
                let start = i
                i += 2
                while i < s.count, !(s[i] == 42 && at(i + 1) == 47), !(s[i] == 60 && at(i + 1) == 63) { i += 1 }
                if at(i) == 42 { i += 2 }
                add(start, min(i, s.count), .comment)
            } else if script, c == 47, at(i + 1) == 47 {  // //
                let start = i
                while i < s.count, s[i] != 10, !stop(i) { i += 1 }
                add(start, i, .comment)
            } else if c == 34 || c == 39 || (script && c == 96) {
                let start = i
                i += 1
                while i < s.count, s[i] != c, !(s[i] == 10 && c != 96), !(s[i] == 60 && at(i + 1) == 63) {
                    i += s[i] == 92 ? 2 : 1
                }
                if at(i) == c { i += 1 }
                add(start, min(i, s.count), .string)
            } else if !script, c == 35, Self.isHexDigit(at(i + 1)) {  // #333 / #ff8800
                let start = i
                i += 1
                while Self.isHexDigit(at(i)) { i += 1 }
                add(start, i, .number)
            } else if Self.isDigit(c), i == 0 || !Self.isIdent(s[i - 1]) {
                let start = i
                while Self.isIdent(at(i)) || at(i) == 46 || at(i) == 37 { i += 1 }  // 12px, 1.5em, 50%
                add(start, i, .number)
            } else if script, Self.isIdentStart(c), i == 0 || !Self.isIdent(s[i - 1]) {
                let start = i
                while Self.isIdent(at(i)) || at(i) == 36 { i += 1 }
                let word = String(decoding: s[start..<i], as: UTF16.self)
                if jsKeywords.contains(word) { add(start, i, .keyword) }
                else if at(i) == 40 { add(start, i, .function) }
            } else {
                i += 1
            }
        }

        static func isHexDigit(_ c: UInt16) -> Bool { isDigit(c) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70) }
        static func isTagStart(_ c: UInt16) -> Bool { (c >= 97 && c <= 122) || (c >= 65 && c <= 90) }
        static func isTagName(_ c: UInt16) -> Bool { isTagStart(c) || isDigit(c) || c == 45 || c == 58 || c == 95 }

        mutating func php() {
            while i < s.count {
                let c = s[i]
                switch c {
                case 63 where at(i + 1) == 62:  // ?>
                    add(i, i + 2, .phpTag)
                    i += 2
                    return
                case 35 where at(i + 1) == 91:  // #[
                    attribute()
                case 35:  // #
                    lineComment()
                case 47 where at(i + 1) == 47:  // //
                    lineComment()
                case 47 where at(i + 1) == 42:  // /*
                    blockComment()
                case 39:  // '
                    quoted(39, interpolate: false)
                case 34:  // "
                    quoted(34, interpolate: true)
                case 96:  // `
                    quoted(96, interpolate: true)
                case 60 where starts("<<<", at: i):
                    if !heredoc() { i += 3 }
                case 36 where Self.isIdentStart(at(i + 1)):  // $name
                    let start = i
                    i += 1
                    while Self.isIdent(at(i)) { i += 1 }
                    let name = String(decoding: s[start..<i], as: UTF16.self)
                    add(start, i, name == "$this" ? .builtin : .variable)
                    previousWord = ""
                case _ where Self.isDigit(c) || (c == 46 && Self.isDigit(at(i + 1))):
                    number()
                case _ where Self.isIdentStart(c):
                    identifier()
                default:
                    if !Self.isSpace(c) && c != 92 { previousWord = "" }  // `\` keeps `new \Foo\Bar` a type
                    i += 1
                }
            }
        }

        /// `//` or `#` comments end at the newline or at `?>`.
        mutating func lineComment() {
            let start = i
            while i < s.count, s[i] != 10, !(s[i] == 63 && at(i + 1) == 62) { i += 1 }
            add(start, i, .comment)
        }

        mutating func blockComment() {
            let start = i
            let isDoc = at(i + 2) == 42 && at(i + 3) != 47  // /** but not /**/
            i += 2
            while i < s.count, !(s[i] == 42 && at(i + 1) == 47) { i += 1 }
            i = min(i + 2, s.count)
            add(start, i, .comment)
            guard isDoc else { return }
            var k = start
            while k < i {
                if s[k] == 64, Self.isIdentStart(at(k + 1)), k == start || !Self.isIdent(s[k - 1]) {  // @tag
                    let tagStart = k
                    k += 1
                    while k < i, Self.isIdent(s[k]) || s[k] == 45 { k += 1 }
                    add(tagStart, k, .docTag)
                } else {
                    k += 1
                }
            }
        }

        /// `#[Name(args)]`: the `#[` and the attribute names are colored; arguments lex normally.
        mutating func attribute() {
            add(i, i + 2, .attribute)
            i += 2
            while Self.isSpace(at(i)) { i += 1 }
            let start = i
            while Self.isIdent(at(i)) || at(i) == 92 { i += 1 }
            add(start, i, .attribute)
        }

        mutating func quoted(_ quote: UInt16, interpolate: Bool) {
            let start = i
            i += 1
            var variables: [(Int, Int)] = []
            while i < s.count, s[i] != quote {
                if s[i] == 92 { i += 2; continue }  // backslash escape
                if interpolate, let end = interpolation(at: i) {
                    variables.append((i, end))
                    i = end
                    continue
                }
                i += 1
            }
            i = min(i + 1, s.count)
            add(start, i, .string)
            for (a, b) in variables { add(a, b, .variable) }
        }

        /// `$name`, `$name->prop`, `$name[…]` or `{$expr}` inside an interpolating string: its end.
        func interpolation(at k: Int) -> Int? {
            if s[k] == 123, at(k + 1) == 36 {  // {$ … }
                var depth = 0, j = k
                while j < s.count {
                    if s[j] == 123 { depth += 1 }
                    if s[j] == 125 { depth -= 1; if depth == 0 { return j + 1 } }
                    if s[j] == 10 && depth == 0 { break }
                    j += 1
                }
                return nil
            }
            guard s[k] == 36, Self.isIdentStart(at(k + 1)) else { return nil }
            var j = k + 1
            while Self.isIdent(at(j)) { j += 1 }
            if at(j) == 45, at(j + 1) == 62, Self.isIdentStart(at(j + 2)) {  // ->prop
                j += 2
                while Self.isIdent(at(j)) { j += 1 }
            } else if at(j) == 91 {  // [key]
                var e = j + 1
                while e < s.count, s[e] != 93, s[e] != 10, s[e] != 34 { e += 1 }
                if at(e) == 93 { j = e + 1 }
            }
            return j
        }

        /// `<<<ID`, `<<<"ID"` (heredoc) or `<<<'ID'` (nowdoc) up to the closing identifier line.
        mutating func heredoc() -> Bool {
            let start = i
            var k = i + 3
            while at(k) == 32 || at(k) == 9 { k += 1 }
            var quote: UInt16 = 0
            if at(k) == 39 || at(k) == 34 { quote = at(k); k += 1 }
            let idStart = k
            while Self.isIdent(at(k)) { k += 1 }
            guard k > idStart, Self.isIdentStart(at(idStart)) else { return false }
            let id = Array(s[idStart..<k])
            if quote != 0 { guard at(k) == quote else { return false }; k += 1 }
            guard at(k) == 10 || (at(k) == 13 && at(k + 1) == 10) else { return false }

            let interpolate = quote != 39
            var variables: [(Int, Int)] = []
            var lineStart = k + 1
            var end = s.count
            outer: while lineStart < s.count {
                var j = lineStart
                while at(j) == 32 || at(j) == 9 { j += 1 }  // PHP 7.3+: indented closing marker
                if j + id.count <= s.count, Array(s[j..<j + id.count]) == id, !Self.isIdent(at(j + id.count)) {
                    end = j + id.count
                    break outer
                }
                // Scan this body line.
                j = lineStart
                while j < s.count, s[j] != 10 {
                    if interpolate, s[j] == 92 { j += 2; continue }
                    if interpolate, let e = interpolation(at: j) { variables.append((j, e)); j = e; continue }
                    j += 1
                }
                lineStart = j + 1
            }
            i = min(end, s.count)
            add(start, i, .string)
            for (a, b) in variables { add(a, b, .variable) }
            return true
        }

        mutating func number() {
            let start = i
            if at(i) == 48, [120, 88, 98, 66, 111, 79].contains(at(i + 1)) {  // 0x 0b 0o
                i += 2
                while Self.isIdent(at(i)) { i += 1 }
            } else {
                while Self.isDigit(at(i)) || at(i) == 95 { i += 1 }
                if at(i) == 46, Self.isDigit(at(i + 1)) || !Self.isIdentStart(at(i + 1)) && at(i + 1) != 46 {
                    i += 1
                    while Self.isDigit(at(i)) || at(i) == 95 { i += 1 }
                }
                if at(i) == 101 || at(i) == 69 {  // exponent
                    var k = i + 1
                    if at(k) == 43 || at(k) == 45 { k += 1 }
                    if Self.isDigit(at(k)) { i = k; while Self.isDigit(at(i)) { i += 1 } }
                }
            }
            add(start, i, .number)
            previousWord = ""
        }

        mutating func identifier() {
            let start = i
            while Self.isIdent(at(i)) { i += 1 }
            let word = String(decoding: s[start..<i], as: UTF16.self)
            let lowered = word.lowercased()
            let afterArrow = (start >= 2 && s[start - 1] == 62 && s[start - 2] == 45)  // ->name
            let afterColons = (start >= 2 && s[start - 1] == 58 && s[start - 2] == 58)  // ::name
            var j = i
            while j < s.count, s[j] == 32 || s[j] == 9 { j += 1 }
            let call = at(j) == 40
            let statics = at(j) == 58 && at(j + 1) == 58

            if afterArrow || afterColons {
                if call { add(start, i, .function) }
                else if afterColons, lowered != "class" { add(start, i, .builtin) }  // Foo::CONST
                previousWord = ""
                return
            }
            if keywords.contains(lowered), !(lowered == "static" && statics) {
                add(start, i, .keyword)
            } else if builtins.contains(lowered) {
                add(start, i, .builtin)
            } else if types.contains(lowered) {
                add(start, i, .type)
            } else if typeIntroducers.contains(previousWord) || statics {
                add(start, i, .type)
            } else if call {
                add(start, i, .function)
            }
            // A namespaced name (`new \App\Models\User`) keeps the introducer alive across segments.
            if !(typeIntroducers.contains(previousWord) && at(i) == 92) {
                previousWord = lowered
            }
            if lowered == "implements" || lowered == "extends" { previousWord = lowered }
        }
    }
}
