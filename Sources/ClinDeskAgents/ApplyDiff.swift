import Foundation

public enum ApplyDiffMode: String, Sendable {
    case `default`
    case create
}

public struct ApplyDiffError: Error, Equatable, LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

struct ApplyDiffChunk: Equatable, Sendable {
    var originalIndex: Int
    var deletedLines: [String]
    var insertedLines: [String]
}

struct ApplyDiffParserState: Equatable, Sendable {
    var lines: [String]
    var index: Int = 0
    var fuzz: Int = 0
}

struct ParsedApplyDiff: Equatable, Sendable {
    var chunks: [ApplyDiffChunk]
    var fuzz: Int
}

struct ApplyDiffReadSectionResult: Equatable, Sendable {
    var nextContext: [String]
    var sectionChunks: [ApplyDiffChunk]
    var endIndex: Int
    var endOfFile: Bool
}

struct ApplyDiffContextMatch: Equatable, Sendable {
    var newIndex: Int
    var fuzz: Int
}

private let applyDiffEndPatch = "*** End Patch"
private let applyDiffEndFile = "*** End of File"
private let applyDiffSectionTerminators = [
    applyDiffEndPatch,
    "*** Update File:",
    "*** Delete File:",
    "*** Add File:"
]
private let applyDiffEndSectionMarkers = applyDiffSectionTerminators + [applyDiffEndFile]

public func applyDiff(
    _ input: String,
    diff: String,
    mode: ApplyDiffMode = .default
) throws -> String {
    let newline = applyDiffDetectNewline(input: input, diff: diff, mode: mode)
    let diffLines = applyDiffNormalizeDiffLines(diff)
    if mode == .create {
        return try applyDiffParseCreateDiff(diffLines, newline: newline)
    }

    let normalizedInput = applyDiffNormalizeTextNewlines(input)
    let parsed = try applyDiffParseUpdateDiff(diffLines, input: normalizedInput)
    return try applyDiffApplyChunks(normalizedInput, chunks: parsed.chunks, newline: newline)
}

func applyDiffNormalizeDiffLines(_ diff: String) -> [String] {
    var lines = applyDiffSplit(diff.replacingOccurrences(of: "\r\n", with: "\n")).map { line in
        var value = line
        while value.last == "\r" {
            value.removeLast()
        }
        return value
    }
    if lines.last == "" {
        lines.removeLast()
    }
    return lines
}

func applyDiffIsDone(_ state: ApplyDiffParserState, prefixes: [String]) -> Bool {
    if state.index >= state.lines.count {
        return true
    }
    return prefixes.contains { state.lines[state.index].hasPrefix($0) }
}

func applyDiffReadString(_ state: inout ApplyDiffParserState, prefix: String) -> String {
    guard state.index < state.lines.count else {
        return ""
    }
    let current = state.lines[state.index]
    guard current.hasPrefix(prefix) else {
        return ""
    }
    state.index += 1
    return String(current.dropFirst(prefix.count))
}

func applyDiffReadSection(
    _ lines: [String],
    startIndex: Int
) throws -> ApplyDiffReadSectionResult {
    var context: [String] = []
    var deletedLines: [String] = []
    var insertedLines: [String] = []
    var sectionChunks: [ApplyDiffChunk] = []
    var mode = ApplyDiffSectionMode.keep
    var index = startIndex
    let originalIndex = index

    while index < lines.count {
        let raw = lines[index]
        if raw.hasPrefix("@@")
            || raw.hasPrefix(applyDiffEndPatch)
            || raw.hasPrefix("*** Update File:")
            || raw.hasPrefix("*** Delete File:")
            || raw.hasPrefix("*** Add File:")
            || raw.hasPrefix(applyDiffEndFile) {
            break
        }
        if raw == "***" {
            break
        }
        if raw.hasPrefix("***") {
            throw ApplyDiffError("Invalid Line: \(raw)")
        }

        index += 1
        let lastMode = mode
        let line = raw.isEmpty ? " " : raw
        let prefix = line[line.startIndex]
        if prefix == "+" {
            mode = .add
        } else if prefix == "-" {
            mode = .delete
        } else if prefix == " " {
            mode = .keep
        } else {
            throw ApplyDiffError("Invalid Line: \(line)")
        }

        let lineContent = String(line.dropFirst())
        let switchingToContext = mode == .keep && lastMode != mode
        if switchingToContext && (!deletedLines.isEmpty || !insertedLines.isEmpty) {
            sectionChunks.append(ApplyDiffChunk(
                originalIndex: context.count - deletedLines.count,
                deletedLines: deletedLines,
                insertedLines: insertedLines
            ))
            deletedLines = []
            insertedLines = []
        }

        switch mode {
        case .delete:
            deletedLines.append(lineContent)
            context.append(lineContent)
        case .add:
            insertedLines.append(lineContent)
        case .keep:
            context.append(lineContent)
        }
    }

    if !deletedLines.isEmpty || !insertedLines.isEmpty {
        sectionChunks.append(ApplyDiffChunk(
            originalIndex: context.count - deletedLines.count,
            deletedLines: deletedLines,
            insertedLines: insertedLines
        ))
    }

    if index < lines.count, lines[index] == applyDiffEndFile {
        return ApplyDiffReadSectionResult(
            nextContext: context,
            sectionChunks: sectionChunks,
            endIndex: index + 1,
            endOfFile: true
        )
    }

    if index == originalIndex {
        let nextLine = index < lines.count ? lines[index] : ""
        throw ApplyDiffError("Nothing in this section - index=\(index) \(nextLine)")
    }

    return ApplyDiffReadSectionResult(
        nextContext: context,
        sectionChunks: sectionChunks,
        endIndex: index,
        endOfFile: false
    )
}

func applyDiffFindContext(
    lines: [String],
    context: [String],
    start: Int,
    endOfFile: Bool
) -> ApplyDiffContextMatch {
    if endOfFile {
        let endStart = max(0, lines.count - context.count)
        let endMatch = applyDiffFindContextCore(lines: lines, context: context, start: endStart)
        if endMatch.newIndex != -1 {
            return endMatch
        }
        let fallback = applyDiffFindContextCore(lines: lines, context: context, start: start)
        return ApplyDiffContextMatch(newIndex: fallback.newIndex, fuzz: fallback.fuzz + 10_000)
    }
    return applyDiffFindContextCore(lines: lines, context: context, start: start)
}

func applyDiffFindContextCore(
    lines: [String],
    context: [String],
    start: Int
) -> ApplyDiffContextMatch {
    if context.isEmpty {
        return ApplyDiffContextMatch(newIndex: start, fuzz: 0)
    }

    for index in start..<lines.count where applyDiffEqualsSlice(lines, context, index, { $0 }) {
        return ApplyDiffContextMatch(newIndex: index, fuzz: 0)
    }
    for index in start..<lines.count where applyDiffEqualsSlice(lines, context, index, { $0.trimmedRight }) {
        return ApplyDiffContextMatch(newIndex: index, fuzz: 1)
    }
    for index in start..<lines.count where applyDiffEqualsSlice(lines, context, index, { $0.trimmed }) {
        return ApplyDiffContextMatch(newIndex: index, fuzz: 100)
    }

    return ApplyDiffContextMatch(newIndex: -1, fuzz: 0)
}

func applyDiffApplyChunks(
    _ input: String,
    chunks: [ApplyDiffChunk],
    newline: String
) throws -> String {
    let originalLines = applyDiffSplit(input)
    var destinationLines: [String] = []
    var cursor = 0

    for chunk in chunks {
        if chunk.originalIndex > originalLines.count {
            throw ApplyDiffError(
                "applyDiff: chunk.origIndex \(chunk.originalIndex) > input length \(originalLines.count)"
            )
        }
        if cursor > chunk.originalIndex {
            throw ApplyDiffError(
                "applyDiff: overlapping chunk at \(chunk.originalIndex) (cursor \(cursor))"
            )
        }

        destinationLines.append(contentsOf: originalLines[cursor..<chunk.originalIndex])
        cursor = chunk.originalIndex
        if !chunk.insertedLines.isEmpty {
            destinationLines.append(contentsOf: chunk.insertedLines)
        }
        cursor += chunk.deletedLines.count
    }

    destinationLines.append(contentsOf: originalLines[cursor...])
    return destinationLines.joined(separator: newline)
}

private enum ApplyDiffSectionMode {
    case keep
    case add
    case delete
}

private func applyDiffDetectNewline(input: String, diff: String, mode: ApplyDiffMode) -> String {
    if mode != .create, applyDiffContainsLineFeed(input) {
        return applyDiffDetectNewline(from: input)
    }
    return applyDiffDetectNewline(from: diff)
}

private func applyDiffDetectNewline(from text: String) -> String {
    applyDiffContainsCRLF(text) ? "\r\n" : "\n"
}

private func applyDiffContainsLineFeed(_ text: String) -> Bool {
    text.unicodeScalars.contains { $0.value == 10 }
}

private func applyDiffContainsCRLF(_ text: String) -> Bool {
    var previousWasCR = false
    for scalar in text.unicodeScalars {
        if previousWasCR, scalar.value == 10 {
            return true
        }
        previousWasCR = scalar.value == 13
    }
    return false
}

private func applyDiffNormalizeTextNewlines(_ text: String) -> String {
    text.replacingOccurrences(of: "\r\n", with: "\n")
}

private func applyDiffParseCreateDiff(_ lines: [String], newline: String) throws -> String {
    var parser = ApplyDiffParserState(lines: lines + [applyDiffEndPatch])
    var output: [String] = []

    while !applyDiffIsDone(parser, prefixes: applyDiffSectionTerminators) {
        if parser.index >= parser.lines.count {
            break
        }
        let line = parser.lines[parser.index]
        parser.index += 1
        guard line.hasPrefix("+") else {
            throw ApplyDiffError("Invalid Add File Line: \(line)")
        }
        output.append(String(line.dropFirst()))
    }

    return output.joined(separator: newline)
}

private func applyDiffParseUpdateDiff(
    _ lines: [String],
    input: String
) throws -> ParsedApplyDiff {
    var parser = ApplyDiffParserState(lines: lines + [applyDiffEndPatch])
    let inputLines = applyDiffSplit(input)
    var chunks: [ApplyDiffChunk] = []
    var cursor = 0

    while !applyDiffIsDone(parser, prefixes: applyDiffEndSectionMarkers) {
        let anchor = applyDiffReadString(&parser, prefix: "@@ ")
        let hasBareAnchor = anchor.isEmpty
            && parser.index < parser.lines.count
            && parser.lines[parser.index] == "@@"
        if hasBareAnchor {
            parser.index += 1
        }

        if !(anchor.isEmpty == false || hasBareAnchor || cursor == 0) {
            let currentLine = parser.index < parser.lines.count ? parser.lines[parser.index] : ""
            throw ApplyDiffError("Invalid Line:\n\(currentLine)")
        }

        if !anchor.trimmed.isEmpty {
            cursor = applyDiffAdvanceCursorToAnchor(
                anchor,
                inputLines: inputLines,
                cursor: cursor,
                parser: &parser
            )
        }

        let section = try applyDiffReadSection(parser.lines, startIndex: parser.index)
        let findResult = applyDiffFindContext(
            lines: inputLines,
            context: section.nextContext,
            start: cursor,
            endOfFile: section.endOfFile
        )
        if findResult.newIndex == -1 {
            let contextText = section.nextContext.joined(separator: "\n")
            if section.endOfFile {
                throw ApplyDiffError("Invalid EOF Context \(cursor):\n\(contextText)")
            }
            throw ApplyDiffError("Invalid Context \(cursor):\n\(contextText)")
        }

        cursor = findResult.newIndex + section.nextContext.count
        parser.fuzz += findResult.fuzz
        parser.index = section.endIndex

        for chunk in section.sectionChunks {
            chunks.append(ApplyDiffChunk(
                originalIndex: chunk.originalIndex + findResult.newIndex,
                deletedLines: chunk.deletedLines,
                insertedLines: chunk.insertedLines
            ))
        }
    }

    return ParsedApplyDiff(chunks: chunks, fuzz: parser.fuzz)
}

private func applyDiffAdvanceCursorToAnchor(
    _ anchor: String,
    inputLines: [String],
    cursor: Int,
    parser: inout ApplyDiffParserState
) -> Int {
    var cursor = cursor
    var found = false

    if !inputLines[..<cursor].contains(anchor) {
        for index in cursor..<inputLines.count where inputLines[index] == anchor {
            cursor = index + 1
            found = true
            break
        }
    }

    if !found && !inputLines[..<cursor].contains(where: { $0.trimmed == anchor.trimmed }) {
        for index in cursor..<inputLines.count where inputLines[index].trimmed == anchor.trimmed {
            cursor = index + 1
            parser.fuzz += 1
            found = true
            break
        }
    }

    return cursor
}

private func applyDiffEqualsSlice(
    _ source: [String],
    _ target: [String],
    _ start: Int,
    _ transform: (String) -> String
) -> Bool {
    if start + target.count > source.count {
        return false
    }
    for offset in 0..<target.count where transform(source[start + offset]) != transform(target[offset]) {
        return false
    }
    return true
}

private func applyDiffSplit(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRight: String {
        var value = self
        while value.last?.isWhitespace == true {
            value.removeLast()
        }
        return value
    }
}
