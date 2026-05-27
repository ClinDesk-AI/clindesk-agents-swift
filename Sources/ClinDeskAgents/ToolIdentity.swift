public enum FunctionToolLookupKey: Hashable, Sendable {
    case bare(String)
    case namespaced(namespace: String, name: String)
    case deferredTopLevel(String)

    public func toDictionary() -> [String: JSONValue] {
        switch self {
        case .bare(let name):
            return [
                "kind": "bare",
                "name": .string(name)
            ]
        case .namespaced(let namespace, let name):
            return [
                "kind": "namespaced",
                "namespace": .string(namespace),
                "name": .string(name)
            ]
        case .deferredTopLevel(let name):
            return [
                "kind": "deferred_top_level",
                "name": .string(name)
            ]
        }
    }

    public init?(dictionary: [String: JSONValue]) {
        guard let kind = dictionary["kind"]?.stringValue,
              let name = dictionary["name"]?.stringValue,
              !name.isEmpty
        else {
            return nil
        }

        switch kind {
        case "bare":
            self = .bare(name)
        case "deferred_top_level":
            self = .deferredTopLevel(name)
        case "namespaced":
            guard let namespace = dictionary["namespace"]?.stringValue, !namespace.isEmpty else {
                return nil
            }
            self = .namespaced(namespace: namespace, name: name)
        default:
            return nil
        }
    }
}

public enum ToolIdentity {
    public static func qualifiedName(name: String?, namespace: String? = nil) -> String? {
        guard let name, !name.isEmpty else {
            return nil
        }
        guard let namespace, !namespace.isEmpty else {
            return name
        }
        return "\(namespace).\(name)"
    }

    public static func traceName(name: String?, namespace: String? = nil) -> String? {
        if isReservedSyntheticNamespace(name: name, namespace: namespace) {
            return name
        }
        return qualifiedName(name: name, namespace: namespace)
    }

    public static func toolCallNamespace(_ call: FunctionCall) -> String? {
        explicitNamespace(call.namespace)
    }

    public static func toolCallName(_ call: FunctionCall) -> String? {
        guard !call.name.isEmpty else {
            return nil
        }
        return call.name
    }

    public static func toolCallQualifiedName(_ call: FunctionCall) -> String? {
        qualifiedName(
            name: toolCallName(call),
            namespace: toolCallNamespace(call)
        )
    }

    public static func toolCallTraceName(_ call: FunctionCall) -> String? {
        traceName(
            name: toolCallName(call),
            namespace: toolCallNamespace(call)
        )
    }

    public static func isReservedSyntheticNamespace(name: String?, namespace: String?) -> Bool {
        guard let name, !name.isEmpty, let namespace, !namespace.isEmpty else {
            return false
        }
        return name == namespace
    }

    public static func functionToolLookupKey(
        name: String?,
        namespace: String? = nil
    ) -> FunctionToolLookupKey? {
        guard let name, !name.isEmpty else {
            return nil
        }
        if isReservedSyntheticNamespace(name: name, namespace: namespace) {
            return .deferredTopLevel(name)
        }
        if let namespace, !namespace.isEmpty {
            return .namespaced(namespace: namespace, name: name)
        }
        return .bare(name)
    }

    public static func functionToolLookupKey(for call: FunctionCall) -> FunctionToolLookupKey? {
        functionToolLookupKey(
            name: toolCallName(call),
            namespace: toolCallNamespace(call)
        )
    }

    public static func isDeferredTopLevelFunctionTool<Context: Sendable>(
        _ tool: FunctionTool<Context>
    ) -> Bool {
        tool.descriptor.deferLoading
            && explicitNamespace(tool.descriptor.namespace) == nil
            && !tool.descriptor.name.isEmpty
    }

    public static func functionToolLookupKey<Context: Sendable>(
        for tool: FunctionTool<Context>
    ) -> FunctionToolLookupKey? {
        if isDeferredTopLevelFunctionTool(tool) {
            return .deferredTopLevel(tool.descriptor.name)
        }
        return functionToolLookupKey(
            name: tool.descriptor.name,
            namespace: explicitNamespace(tool.descriptor.namespace)
        )
    }

    public static func functionToolDispatchName<Context: Sendable>(
        for tool: FunctionTool<Context>
    ) -> String? {
        qualifiedName(
            name: tool.descriptor.name,
            namespace: explicitNamespace(tool.descriptor.namespace)
        )
    }

    public static func functionToolQualifiedName<Context: Sendable>(
        for tool: FunctionTool<Context>
    ) -> String? {
        functionToolDispatchName(for: tool)
    }

    public static func functionToolTraceName<Context: Sendable>(
        for tool: FunctionTool<Context>
    ) -> String? {
        traceName(
            name: tool.descriptor.name,
            namespace: explicitNamespace(tool.descriptor.namespace)
        )
    }

    public static func normalizedToolCall<Context: Sendable>(
        _ call: FunctionCall,
        for tool: FunctionTool<Context>
    ) -> FunctionCall {
        guard isDeferredTopLevelFunctionTool(tool),
              call.name == tool.descriptor.name,
              toolCallNamespace(call) == tool.descriptor.name
        else {
            return call
        }
        var normalized = call
        normalized.namespace = nil
        return normalized
    }

    public static func functionToolLookupKeys<Context: Sendable>(
        for tool: FunctionTool<Context>
    ) -> [FunctionToolLookupKey] {
        guard !tool.descriptor.name.isEmpty else {
            return []
        }

        var keys: [FunctionToolLookupKey] = []
        if !isDeferredTopLevelFunctionTool(tool),
           let dispatchKey = functionToolLookupKey(
            name: tool.descriptor.name,
            namespace: explicitNamespace(tool.descriptor.namespace)
           ) {
            keys.append(dispatchKey)
        }
        if isDeferredTopLevelFunctionTool(tool) {
            let syntheticKey = FunctionToolLookupKey.deferredTopLevel(tool.descriptor.name)
            if !keys.contains(syntheticKey) {
                keys.append(syntheticKey)
            }
        }
        return keys
    }

    public static func shouldAllowBareNameApprovalAlias<Context: Sendable>(
        for tool: FunctionTool<Context>,
        allTools: [FunctionTool<Context>]
    ) -> Bool {
        let toolName = tool.descriptor.name
        guard !toolName.isEmpty, isDeferredTopLevelFunctionTool(tool) else {
            return false
        }

        for candidate in allTools where candidate.descriptor.name == toolName {
            if explicitNamespace(candidate.descriptor.namespace) != nil {
                continue
            }
            if candidate.descriptor.deferLoading {
                continue
            }
            return false
        }

        return true
    }

    public static func functionToolApprovalKeys(
        toolName: String?,
        toolNamespace: String? = nil,
        allowBareNameAlias: Bool = false,
        toolLookupKey: FunctionToolLookupKey? = nil,
        preferLegacySameNameNamespace: Bool = false,
        includeLegacyDeferredKey: Bool = false
    ) -> [String] {
        guard let toolName, !toolName.isEmpty else {
            return []
        }

        let namespace = explicitNamespace(toolNamespace)
        var lookupKey = toolLookupKey
        if lookupKey == nil && !(preferLegacySameNameNamespace && isReservedSyntheticNamespace(
            name: toolName,
            namespace: namespace
        )) {
            lookupKey = functionToolLookupKey(name: toolName, namespace: namespace)
        }

        let qualifiedToolName = qualifiedName(name: toolName, namespace: namespace)
        var approvalKeys: [String] = []
        func appendKey(_ key: String?) {
            guard let key, !approvalKeys.contains(key) else {
                return
            }
            approvalKeys.append(key)
        }

        if allowBareNameAlias {
            appendKey(toolName)
        }

        if let lookupKey {
            switch lookupKey {
            case .bare(let name):
                appendKey(name)
            case .namespaced(let namespace, let name):
                appendKey(Self.qualifiedName(name: name, namespace: namespace))
            case .deferredTopLevel(let name):
                appendKey("deferred_top_level:\(name)")
            }

            if includeLegacyDeferredKey,
               case .deferredTopLevel = lookupKey {
                appendKey(qualifiedToolName)
            }
        } else {
            appendKey(qualifiedToolName)
        }

        if approvalKeys.isEmpty {
            approvalKeys.append(toolName)
        }
        return approvalKeys
    }

    public static func validateFunctionToolNamespaceShape(
        name: String?,
        namespace: String?
    ) throws {
        guard isReservedSyntheticNamespace(name: name, namespace: namespace) else {
            return
        }
        let reservedKey = qualifiedName(name: name, namespace: namespace) ?? name ?? "unknown_tool"
        throw AgentsError.invalidRunConfig(
            "Deferred top-level function tools reserve the synthetic namespace `\(reservedKey)`. Rename the namespace or tool name to avoid ambiguous dispatch."
        )
    }

    public static func validateFunctionToolLookupConfiguration<Context: Sendable>(
        _ tools: [FunctionTool<Context>]
    ) throws {
        var qualifiedNameOwners: [String: FunctionTool<Context>] = [:]
        var deferredTopLevelNameOwners = Set<String>()

        for tool in tools {
            let name = tool.descriptor.name
            let namespace = explicitNamespace(tool.descriptor.namespace)
            try validateFunctionToolNamespaceShape(name: name, namespace: namespace)

            if isDeferredTopLevelFunctionTool(tool) {
                if deferredTopLevelNameOwners.contains(name) {
                    throw AgentsError.invalidRunConfig(
                        "Ambiguous function tool configuration: the deferred top-level tool name `\(name)` is used by multiple tools. Rename one of the deferred-loading top-level function tools to avoid ambiguous dispatch."
                    )
                }
                deferredTopLevelNameOwners.insert(name)
            }

            guard let qualifiedName = Self.qualifiedName(name: name, namespace: namespace) else {
                continue
            }
            guard let priorOwner = qualifiedNameOwners[qualifiedName] else {
                qualifiedNameOwners[qualifiedName] = tool
                continue
            }

            if namespace == nil && explicitNamespace(priorOwner.descriptor.namespace) == nil {
                continue
            }

            throw AgentsError.invalidRunConfig(
                "Ambiguous function tool configuration: the qualified name `\(qualifiedName)` is used by multiple tools. Rename the namespace-wrapped function or dotted top-level tool to avoid ambiguous dispatch."
            )
        }
    }

    public static func buildFunctionToolLookupMap<Context: Sendable>(
        _ tools: [FunctionTool<Context>]
    ) throws -> [FunctionToolLookupKey: FunctionTool<Context>] {
        try validateFunctionToolLookupConfiguration(tools)
        var toolMap: [FunctionToolLookupKey: FunctionTool<Context>] = [:]
        for tool in tools {
            for lookupKey in functionToolLookupKeys(for: tool) {
                toolMap[lookupKey] = tool
            }
        }
        return toolMap
    }

    private static func explicitNamespace(_ namespace: String?) -> String? {
        guard let namespace, !namespace.isEmpty else {
            return nil
        }
        return namespace
    }
}
