import Foundation
import ClinDeskAgents

enum RecordedComputerEvent: Equatable, Sendable {
    case click(x: Int, y: Int, button: ComputerButton, keys: [String]?)
    case doubleClick(x: Int, y: Int, keys: [String]?)
    case scroll(x: Int, y: Int, scrollX: Int, scrollY: Int, keys: [String]?)
    case type(String)
    case wait
    case move(x: Int, y: Int, keys: [String]?)
    case keypress([String])
    case drag([ComputerPoint], keys: [String]?)
    case screenshot
}

final class RecordingComputer: Computer, @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [RecordedComputerEvent] = []
    var screenshotImage = "image-data"

    var events: [RecordedComputerEvent] {
        lock.withLock { storedEvents }
    }

    func screenshot() async throws -> String {
        record(.screenshot)
        return screenshotImage
    }

    func click(x: Int, y: Int, button: ComputerButton, keys: [String]?) async throws {
        record(.click(x: x, y: y, button: button, keys: keys))
    }

    func doubleClick(x: Int, y: Int, keys: [String]?) async throws {
        record(.doubleClick(x: x, y: y, keys: keys))
    }

    func scroll(x: Int, y: Int, scrollX: Int, scrollY: Int, keys: [String]?) async throws {
        record(.scroll(x: x, y: y, scrollX: scrollX, scrollY: scrollY, keys: keys))
    }

    func type(_ text: String) async throws {
        record(.type(text))
    }

    func wait() async throws {
        record(.wait)
    }

    func move(x: Int, y: Int, keys: [String]?) async throws {
        record(.move(x: x, y: y, keys: keys))
    }

    func keypress(_ keys: [String]) async throws {
        record(.keypress(keys))
    }

    func drag(path: [ComputerPoint], keys: [String]?) async throws {
        record(.drag(path, keys: keys))
    }

    private func record(_ event: RecordedComputerEvent) {
        lock.withLock {
            storedEvents.append(event)
        }
    }
}

actor ComputerSafetyRecorder {
    private var storedChecks: [PendingComputerSafetyCheck] = []

    func record(_ check: PendingComputerSafetyCheck) {
        storedChecks.append(check)
    }

    func checks() -> [PendingComputerSafetyCheck] {
        storedChecks
    }
}
