import Foundation

/// The kind of a single unified-diff line, driving its color in the Changes panel
/// (SPEC §7 / `Design/HANDOFF.md` "diff / file status").
public enum DiffLineKind: Sendable, Hashable {
    case fileHeader   // `diff --git`, `index`, `--- a/…`, `+++ b/…`, mode lines
    case hunkHeader   // `@@ -a,b +c,d @@`
    case addition     // `+…`
    case deletion     // `-…`
    case context      // unchanged / blank
}

/// One classified line of a unified diff, ready for per-line rendering.
public struct DiffLine: Identifiable, Sendable, Hashable {
    public let id: Int      // 0-based line index within the patch
    public let text: String
    public let kind: DiffLineKind

    public init(id: Int, text: String, kind: DiffLineKind) {
        self.id = id; self.text = text; self.kind = kind
    }
}

/// Pure classification of a unified diff patch into colorable lines. No git/port access —
/// it reads the standard `git show` prefixes off each line.
public enum DiffSyntax {
    public static func classify(_ patch: String) -> [DiffLine] {
        guard !patch.isEmpty else { return [] }
        var body = patch
        if body.hasSuffix("\n") { body.removeLast() }   // git patches end in a newline; no trailing blank row
        return body.components(separatedBy: "\n").enumerated().map { index, text in
            DiffLine(id: index, text: text, kind: kind(ofLine: text))
        }
    }

    static func kind(ofLine line: String) -> DiffLineKind {
        // `---`/`+++` file markers share the +/- sign, so they must be caught before add/delete.
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .fileHeader }
        if line.hasPrefix("@@") { return .hunkHeader }
        if line.hasPrefix("diff --git") || line.hasPrefix("index ")
            || line.hasPrefix("new file") || line.hasPrefix("deleted file")
            || line.hasPrefix("old mode") || line.hasPrefix("new mode")
            || line.hasPrefix("rename ") || line.hasPrefix("similarity ")
            || line.hasPrefix("Binary files") { return .fileHeader }
        if line.hasPrefix("+") { return .addition }
        if line.hasPrefix("-") { return .deletion }
        return .context
    }
}
