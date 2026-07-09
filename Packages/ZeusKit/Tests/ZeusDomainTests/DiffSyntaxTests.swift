import Testing
@testable import ZeusDomain

/// Classifies each line of a unified diff for per-line coloring in the Changes panel
/// (SPEC §7 / `Design/HANDOFF.md` "diff / file status"). Pure string parsing, no ports.
struct DiffSyntaxTests {
    @Test func emptyPatchHasNoLines() {
        #expect(DiffSyntax.classify("").isEmpty)
    }

    @Test func aPlainLineIsContext() {
        let lines = DiffSyntax.classify(" unchanged line")
        #expect(lines.count == 1)
        #expect(lines[0].id == 0)
        #expect(lines[0].text == " unchanged line")
        #expect(lines[0].kind == .context)
    }

    @Test func additionsAndDeletionsAreClassifiedByLeadingSign() {
        #expect(DiffSyntax.classify("+added code")[0].kind == .addition)
        #expect(DiffSyntax.classify("-removed code")[0].kind == .deletion)
    }

    @Test func hunkHeadersAreClassifiedByAtAt() {
        #expect(DiffSyntax.classify("@@ -1,4 +1,6 @@ func body()")[0].kind == .hunkHeader)
    }

    @Test func gitFileHeadersAreClassified() {
        #expect(DiffSyntax.classify("diff --git a/File.swift b/File.swift")[0].kind == .fileHeader)
        #expect(DiffSyntax.classify("index 1a2b3c4..5d6e7f8 100644")[0].kind == .fileHeader)
        #expect(DiffSyntax.classify("new file mode 100644")[0].kind == .fileHeader)
        #expect(DiffSyntax.classify("deleted file mode 100644")[0].kind == .fileHeader)
    }

    // The tricky case: `---`/`+++` file markers start with the same sign as del/add lines,
    // so they MUST be classified as headers first — otherwise the whole file block reads red/green.
    @Test func tripleDashAndPlusMarkersAreHeadersNotChanges() {
        #expect(DiffSyntax.classify("--- a/File.swift")[0].kind == .fileHeader)
        #expect(DiffSyntax.classify("+++ b/File.swift")[0].kind == .fileHeader)
    }

    @Test func multiLinePatchPreservesOrderTextAndSequentialIds() {
        let patch = """
        @@ -1,2 +1,2 @@
         context
        -old
        +new
        """
        let lines = DiffSyntax.classify(patch)
        #expect(lines.map(\.kind) == [.hunkHeader, .context, .deletion, .addition])
        #expect(lines.map(\.id) == [0, 1, 2, 3])
        #expect(lines[2].text == "-old")
    }

    // A patch fresh from `git show` ends in a newline; that must not spawn a trailing blank row.
    @Test func trailingNewlineDoesNotProduceASpuriousEmptyLine() {
        let lines = DiffSyntax.classify("+new\n")
        #expect(lines.count == 1)
        #expect(lines[0].kind == .addition)
    }

    // An interior blank line is meaningful context and is preserved.
    @Test func interiorBlankLineIsPreservedAsContext() {
        let lines = DiffSyntax.classify(" a\n\n b")
        #expect(lines.count == 3)
        #expect(lines[1].text.isEmpty)
        #expect(lines[1].kind == .context)
    }
}
