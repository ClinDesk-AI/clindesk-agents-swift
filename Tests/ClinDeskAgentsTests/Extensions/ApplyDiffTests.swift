import Testing
@testable import ClinDeskAgents

@Suite
struct ApplyDiffTests {
    @Test
    func floatingHunkAddsLinesAndPreservesImplicitTrailingNewline() throws {
        let diff = ["@@", "+hello", "+world"].joined(separator: "\n")

        let output = try applyDiff("", diff: diff)

        #expect(output == "hello\nworld\n")
    }

    @Test
    func floatingHunkWithCRLFDiffPreservesCRLF() throws {
        let diff = ["@@", "+hello", "+world"].joined(separator: "\r\n")

        let output = try applyDiff("", diff: diff)

        #expect(output == "hello\r\nworld\r\n")
    }

    @Test
    func createModeRequiresPlusPrefixedLines() {
        #expect(throws: ApplyDiffError("Invalid Add File Line: plain line")) {
            try applyDiff("", diff: "plain line", mode: .create)
        }
    }

    @Test
    func createModePreservesTrailingNewline() throws {
        let diff = ["+hello", "+world", "+"].joined(separator: "\n")

        let output = try applyDiff("", diff: diff, mode: .create)

        #expect(output == "hello\nworld\n")
    }

    @Test
    func createModePreservesCRLFNewlines() throws {
        let diff = ["+hello", "+world", "+"].joined(separator: "\r\n")

        let output = try applyDiff("", diff: diff, mode: .create)

        #expect(output == "hello\r\nworld\r\n")
    }

    @Test
    func contextualReplacementPreservesInputNewlineStyle() throws {
        let input = "line1\r\nline2\r\nline3\r\n"
        let diff = ["@@ line1", "-line2", "+updated", " line3"].joined(separator: "\n")

        let output = try applyDiff(input, diff: diff)

        #expect(output == "line1\r\nupdated\r\nline3\r\n")
    }

    @Test
    func lfInputWinsOverCRLFDiff() throws {
        let input = "line1\nline2\nline3\n"
        let diff = ["@@ line1", "-line2", "+updated", " line3"].joined(separator: "\r\n")

        let output = try applyDiff(input, diff: diff)

        #expect(output == "line1\nupdated\nline3\n")
    }

    @Test
    func contextMismatchThrows() {
        let diff = ["@@ -1,2 +1,2 @@", " x", "-two", "+2"].joined(separator: "\n")

        #expect(throws: ApplyDiffError("Invalid Context 0:\nx\ntwo")) {
            try applyDiff("one\ntwo\n", diff: diff)
        }
    }

    @Test
    func helperNormalizationDropsTrailingBlankLine() {
        #expect(applyDiffNormalizeDiffLines("a\nb\n") == ["a", "b"])
    }

    @Test
    func helperFindContextSupportsStrippedMatches() {
        let match = applyDiffFindContextCore(lines: [" line "], context: ["line"], start: 0)

        #expect(match == ApplyDiffContextMatch(newIndex: 0, fuzz: 100))
    }

    @Test
    func helperApplyChunksRejectsOutOfRangeAndOverlappingChunks() {
        #expect(throws: ApplyDiffError("applyDiff: chunk.origIndex 10 > input length 1")) {
            try applyDiffApplyChunks(
                "abc",
                chunks: [ApplyDiffChunk(originalIndex: 10, deletedLines: [], insertedLines: [])],
                newline: "\n"
            )
        }

        #expect(throws: ApplyDiffError("applyDiff: overlapping chunk at 0 (cursor 1)")) {
            try applyDiffApplyChunks(
                "abc",
                chunks: [
                    ApplyDiffChunk(originalIndex: 0, deletedLines: ["a"], insertedLines: []),
                    ApplyDiffChunk(originalIndex: 0, deletedLines: ["b"], insertedLines: [])
                ],
                newline: "\n"
            )
        }
    }
}
