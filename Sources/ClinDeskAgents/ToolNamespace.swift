import Foundation

public func toolNamespace<Context: Sendable>(
    name: String,
    description: String,
    tools: [FunctionTool<Context>]
) throws -> [FunctionTool<Context>] {
    let namespace = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let namespaceDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !namespace.isEmpty else {
        throw AgentsError.invalidRunConfig("toolNamespace requires a non-empty namespace name.")
    }
    guard !namespaceDescription.isEmpty else {
        throw AgentsError.invalidRunConfig("toolNamespace requires a non-empty description.")
    }

    return try tools.map { tool in
        if tool.descriptor.name == namespace {
            throw AgentsError.invalidRunConfig(
                "Deferred top-level function tools reserve namespaces that match the inner tool name."
            )
        }
        var namespacedTool = tool
        namespacedTool.descriptor.namespace = namespace
        namespacedTool.descriptor.namespaceDescription = namespaceDescription
        return namespacedTool
    }
}
