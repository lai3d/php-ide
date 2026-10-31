import Foundation

/// File/line references in tool output (php, PHPUnit, PHPStan, composer), for clickable links.
public enum OutputReferences {
    // `file.php:12`, `file.php(12)`, `file.php on line 12` / `file.php, line 12`.
    private static let regex = try! NSRegularExpression(
        pattern: #"((?:[\w.~-]+/|/)*[\w.-]+\.(?:php|phtml|inc|go))(?::(\d+)|\((\d+)\)|,? on line (\d+)|, line (\d+))"#)

    /// The references in `line` with their ranges in it (the whole `file…line` text).
    public static func fileReferences(in line: String) -> [(range: NSRange, file: String, line: Int)] {
        let ns = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let number = (2...5).lazy.map { match.range(at: $0) }.first { $0.location != NSNotFound }
                .flatMap { Int(ns.substring(with: $0)) }
            guard let number else { return nil }
            return (match.range, ns.substring(with: match.range(at: 1)), number)
        }
    }
}
