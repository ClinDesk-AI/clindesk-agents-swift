import Foundation
import ClinDeskAgents

enum SQLiteSessionTestSupport {
    static func temporaryDatabasePath(_ filename: String = "session.db") throws -> (path: String, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return (
            directory.appendingPathComponent(filename).path,
            { try? FileManager.default.removeItem(at: directory) }
        )
    }

    static func message(_ role: AgentMessage.Role, _ content: String) -> ModelInputItem {
        .message(AgentMessage(role: role, content: content))
    }
}

extension ModelInputItem {
    var testMessageContent: String? {
        if case .message(let message) = self {
            return message.content
        }
        return nil
    }
}
