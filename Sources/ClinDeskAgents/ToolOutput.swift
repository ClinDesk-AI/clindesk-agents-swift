import Foundation

public struct ToolOutputText: Codable, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public enum ToolOutputImageDetail: String, Codable, Equatable, Sendable {
    case low
    case high
    case auto
}

public struct ToolOutputImage: Codable, Equatable, Sendable {
    public var imageURL: String?
    public var fileID: String?
    public var detail: ToolOutputImageDetail?

    public init(
        imageURL: String? = nil,
        fileID: String? = nil,
        detail: ToolOutputImageDetail? = nil
    ) {
        self.imageURL = imageURL
        self.fileID = fileID
        self.detail = detail
    }

    public func validate() throws {
        guard imageURL != nil || fileID != nil else {
            throw AgentsError.invalidToolOutput("At least one of image_url or file_id must be provided.")
        }
    }
}

public struct ToolOutputFileContent: Codable, Equatable, Sendable {
    public var fileData: String?
    public var fileURL: String?
    public var fileID: String?
    public var filename: String?

    public init(
        fileData: String? = nil,
        fileURL: String? = nil,
        fileID: String? = nil,
        filename: String? = nil
    ) {
        self.fileData = fileData
        self.fileURL = fileURL
        self.fileID = fileID
        self.filename = filename
    }

    public func validate() throws {
        guard fileData != nil || fileURL != nil || fileID != nil else {
            throw AgentsError.invalidToolOutput(
                "At least one of file_data, file_url, or file_id must be provided."
            )
        }
    }
}

public enum ToolOutputContent: Equatable, Sendable {
    case text(ToolOutputText)
    case image(ToolOutputImage)
    case file(ToolOutputFileContent)

    public static func text(_ text: String) -> ToolOutputContent {
        .text(ToolOutputText(text: text))
    }

    public func validate() throws {
        switch self {
        case .text:
            break
        case .image(let image):
            try image.validate()
        case .file(let file):
            try file.validate()
        }
    }
}

public enum ToolOutput: Equatable, Sendable {
    case text(String)
    case json(JSONValue)
    case structured([ToolOutputContent])

    public var modelValue: JSONValue {
        switch self {
        case .text(let text):
            return .string(text)
        case .json(let value):
            return value
        case .structured(let items):
            return .array(items.map(\.responsesInputValue))
        }
    }

    public var finalOutputText: String {
        switch self {
        case .text(let text):
            return text
        case .json(let value):
            return value.prettyPrinted()
        case .structured(let items):
            return JSONValue.array(items.map(\.responsesInputValue)).prettyPrinted()
        }
    }

    public func validate() throws {
        switch self {
        case .text, .json:
            break
        case .structured(let items):
            for item in items {
                try item.validate()
            }
        }
    }
}

public extension ToolOutputContent {
    var responsesInputValue: JSONValue {
        switch self {
        case .text(let text):
            return [
                "type": "input_text",
                "text": .string(text.text)
            ]
        case .image(let image):
            var payload: [String: JSONValue] = [
                "type": "input_image"
            ]
            if let imageURL = image.imageURL {
                payload["image_url"] = .string(imageURL)
            }
            if let fileID = image.fileID {
                payload["file_id"] = .string(fileID)
            }
            if let detail = image.detail {
                payload["detail"] = .string(detail.rawValue)
            }
            return .object(payload)
        case .file(let file):
            var payload: [String: JSONValue] = [
                "type": "input_file"
            ]
            if let fileData = file.fileData {
                payload["file_data"] = .string(fileData)
            }
            if let fileURL = file.fileURL {
                payload["file_url"] = .string(fileURL)
            }
            if let fileID = file.fileID {
                payload["file_id"] = .string(fileID)
            }
            if let filename = file.filename {
                payload["filename"] = .string(filename)
            }
            return .object(payload)
        }
    }
}
