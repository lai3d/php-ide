import Foundation

/// Bits of a project's composer.json the IDE uses.
public enum Composer {
    /// Script names from `scripts` (custom commands first, then event hooks like `post-install-cmd`).
    public static func scripts(in root: URL) -> [String] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("composer.json")),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let scripts = json["scripts"]?.objectValue
        else { return [] }
        let isHook = { (name: String) in name.hasPrefix("pre-") || name.hasPrefix("post-") }
        return scripts.keys.sorted { a, b in
            isHook(a) != isHook(b) ? !isHook(a) : a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}
