import Foundation

enum RunGroupingKind: String, Sendable {
    case conversation
    case session
    case group
    case run
}

struct RunGrouping: Equatable, Sendable {
    var kind: RunGroupingKind
    var value: String
}

enum RunGroupingResolver {
    static func resolve(
        conversationID: String? = nil,
        session: (any Session)?,
        groupID: String?
    ) -> RunGrouping {
        if let conversationID = nonEmptyTrimmed(conversationID) {
            return RunGrouping(kind: .conversation, value: conversationID)
        }
        if let sessionID = sessionIDIfAvailable(session) {
            return RunGrouping(kind: .session, value: sessionID)
        }
        if let groupID = nonEmptyTrimmed(groupID) {
            return RunGrouping(kind: .group, value: groupID)
        }
        return RunGrouping(
            kind: .run,
            value: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        )
    }

    static func resolveID(
        conversationID: String? = nil,
        session: (any Session)?,
        groupID: String?
    ) -> String {
        let grouping = resolve(conversationID: conversationID, session: session, groupID: groupID)
        switch grouping.kind {
        case .run:
            return "run-\(grouping.value)"
        case .conversation, .session, .group:
            return grouping.value
        }
    }

    static func sessionIDIfAvailable(_ session: (any Session)?) -> String? {
        nonEmptyTrimmed(session?.sessionID)
    }

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
