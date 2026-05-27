import Testing
import ClinDeskAgents

@Suite
struct FunctionToolIdentityTests {
    @Test
    func functionToolLookupKeysSerializeUsingUpstreamShape() {
        let namespaced = FunctionToolLookupKey.namespaced(namespace: "crm", name: "lookup")
        let serialized = namespaced.toDictionary()

        #expect(serialized == [
            "kind": "namespaced",
            "namespace": .string("crm"),
            "name": .string("lookup")
        ])
        #expect(FunctionToolLookupKey(dictionary: serialized) == namespaced)
        #expect(FunctionToolLookupKey(dictionary: [
            "kind": "deferred_top_level",
            "name": .string("search")
        ]) == .deferredTopLevel("search"))
        #expect(FunctionToolLookupKey(dictionary: [
            "kind": "bare",
            "name": .string("search")
        ]) == .bare("search"))
        #expect(FunctionToolLookupKey(dictionary: [
            "kind": "namespaced",
            "name": .string("lookup")
        ]) == nil)
    }

    @Test
    func toolCallHelpersMirrorUpstreamIdentityNames() {
        let namespaced = FunctionCall(
            callID: "call_lookup",
            name: "lookup",
            namespace: "crm",
            arguments: [:]
        )
        let deferredWireCall = FunctionCall(
            callID: "call_search",
            name: "search",
            namespace: "search",
            arguments: [:]
        )
        let unnamed = FunctionCall(callID: "call_empty", name: "", arguments: [:])

        #expect(ToolIdentity.toolCallName(namespaced) == "lookup")
        #expect(ToolIdentity.toolCallNamespace(namespaced) == "crm")
        #expect(ToolIdentity.toolCallQualifiedName(namespaced) == "crm.lookup")
        #expect(ToolIdentity.toolCallTraceName(namespaced) == "crm.lookup")
        #expect(ToolIdentity.functionToolLookupKey(for: namespaced) == .namespaced(namespace: "crm", name: "lookup"))

        #expect(ToolIdentity.toolCallQualifiedName(deferredWireCall) == "search.search")
        #expect(ToolIdentity.toolCallTraceName(deferredWireCall) == "search")
        #expect(ToolIdentity.functionToolLookupKey(for: deferredWireCall) == .deferredTopLevel("search"))
        #expect(ToolIdentity.toolCallName(unnamed) == nil)
        #expect(ToolIdentity.functionToolLookupKey(for: unnamed) == nil)
    }

    @Test
    func functionToolHelpersMirrorUpstreamDispatchAndTraceNames() {
        var namespaced = FunctionTool<Void>(name: "lookup", description: "Lookup.") { _, _ in
            .text("lookup")
        }
        namespaced.descriptor.namespace = "crm"

        let deferred = FunctionTool<Void>(
            name: "search",
            description: "Search.",
            deferLoading: true
        ) { _, _ in
            .text("search")
        }
        let syntheticCall = FunctionCall(
            callID: "call_search",
            name: "search",
            namespace: "search",
            arguments: [:]
        )
        let normalizedCall = ToolIdentity.normalizedToolCall(syntheticCall, for: deferred)

        #expect(ToolIdentity.functionToolDispatchName(for: namespaced) == "crm.lookup")
        #expect(ToolIdentity.functionToolQualifiedName(for: namespaced) == "crm.lookup")
        #expect(ToolIdentity.functionToolTraceName(for: namespaced) == "crm.lookup")
        #expect(ToolIdentity.functionToolDispatchName(for: deferred) == "search")
        #expect(ToolIdentity.functionToolTraceName(for: deferred) == "search")
        #expect(normalizedCall.name == "search")
        #expect(normalizedCall.namespace == nil)
    }

    @Test
    func toolIdentityRejectsReservedSyntheticNamespaceShape() throws {
        var tool = FunctionTool<Void>(
            name: "search",
            description: "Search.",
            deferLoading: true
        ) { _, _ in
            .text("search")
        }
        tool.descriptor.namespace = "search"

        #expect(throws: AgentsError.invalidRunConfig(
            "Deferred top-level function tools reserve the synthetic namespace `search.search`. Rename the namespace or tool name to avoid ambiguous dispatch."
        )) {
            try ToolIdentity.validateFunctionToolLookupConfiguration([tool])
        }
    }
}
