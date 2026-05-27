import Foundation

public struct ToolDescriptor: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONValue
    public var strict: Bool
    public var deferLoading: Bool
    public var namespace: String?
    public var namespaceDescription: String?

    public init(
        name: String,
        description: String,
        parameters: JSONValue = .emptyObject,
        strict: Bool = true,
        deferLoading: Bool = false,
        namespace: String? = nil,
        namespaceDescription: String? = nil
    ) {
        self.name = name
        self.description = description
        self.strict = strict
        self.parameters = strict
            ? (try? StrictSchema.ensureStrictJSONSchema(parameters)) ?? parameters
            : parameters
        self.deferLoading = deferLoading
        self.namespace = namespace
        self.namespaceDescription = namespaceDescription
    }

    public var qualifiedName: String {
        guard let namespace, !namespace.isEmpty else {
            return name
        }
        return "\(namespace).\(name)"
    }
}

public struct CustomToolDescriptor: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var format: JSONValue?
    public var deferLoading: Bool

    public init(
        name: String,
        description: String,
        format: JSONValue? = nil,
        deferLoading: Bool = false
    ) {
        self.name = name
        self.description = description
        self.format = format
        self.deferLoading = deferLoading
    }
}
