import Testing
import ClinDeskAgents

@Suite
struct RunContextApprovalTests {
    @Test
    func latestApprovalDecisionWinsForCallID() {
        var context = RunContext<Void>()
        let approvalItem = ToolApprovalItem(
            toolName: "test_tool",
            callID: "call-1",
            arguments: [:],
            tool: .function(ToolDescriptor(name: "test_tool", description: "Test tool."))
        )

        context.approveTool(approvalItem)
        #expect(context.approvalStatus(toolName: "test_tool", callID: "call-1") == true)

        context.rejectTool(approvalItem)
        #expect(context.approvalStatus(toolName: "test_tool", callID: "call-1") == false)

        context.approveTool(approvalItem)
        #expect(context.approvalStatus(toolName: "test_tool", callID: "call-1") == true)
    }

    @Test
    func namespacedApprovalStatusDoesNotFallBackToBareToolDecisions() {
        var context = RunContext<Void>()
        let bareItem = ToolApprovalItem(
            toolName: "lookup_account",
            callID: "call-bare",
            arguments: [:],
            tool: .function(ToolDescriptor(name: "lookup_account", description: "Lookup account."))
        )
        let billingDescriptor = ToolDescriptor(
            name: "lookup_account",
            description: "Lookup account.",
            namespace: "billing",
            namespaceDescription: "Billing tools"
        )
        let billingItem = ToolApprovalItem(
            toolName: "lookup_account",
            callID: "call-billing",
            arguments: [:],
            tool: .function(billingDescriptor),
            toolNamespace: "billing"
        )

        context.approveTool(bareItem, alwaysApprove: true)

        #expect(context.approvalStatus(
            toolName: "lookup_account",
            callID: "call-billing-2",
            toolNamespace: "billing",
            existingPending: billingItem
        ) == nil)
        #expect(context.approvalStatus(
            toolName: "lookup_account",
            callID: "call-billing-2",
            existingPending: billingItem
        ) == nil)
        #expect(context.approvalStatus(toolName: "lookup_account", callID: "call-bare-2") == true)
    }

    @Test
    func namespacedRejectionMessageDoesNotFallBackToBareToolDecisions() {
        var context = RunContext<Void>()
        let bareItem = ToolApprovalItem(
            toolName: "lookup_account",
            callID: "call-bare",
            arguments: [:],
            tool: .function(ToolDescriptor(name: "lookup_account", description: "Lookup account."))
        )
        let billingItem = ToolApprovalItem(
            toolName: "lookup_account",
            callID: "call-billing",
            arguments: [:],
            tool: .function(ToolDescriptor(
                name: "lookup_account",
                description: "Lookup account.",
                namespace: "billing",
                namespaceDescription: "Billing tools"
            )),
            toolNamespace: "billing"
        )

        context.rejectTool(bareItem, alwaysReject: true, rejectionMessage: "bare denial")

        #expect(context.rejectionMessage(
            toolName: "lookup_account",
            callID: "call-billing-2",
            toolNamespace: "billing",
            existingPending: billingItem
        ) == nil)
        #expect(context.rejectionMessage(toolName: "lookup_account", callID: "call-bare-2") == "bare denial")
    }

    @Test
    func deferredTopLevelPerCallApprovalKeepsBareNameLookup() {
        var context = RunContext<Void>()
        let deferredItem = ToolApprovalItem(
            toolName: "get_weather",
            callID: "call-weather",
            arguments: [:],
            tool: .function(ToolDescriptor(
                name: "get_weather",
                description: "Get weather.",
                deferLoading: true
            )),
            toolNamespace: "get_weather",
            allowBareNameAlias: true,
            toolLookupKey: .deferredTopLevel("get_weather")
        )

        context.approveTool(deferredItem)

        #expect(context.approvalStatus(toolName: "get_weather", callID: "call-weather") == true)
        #expect(context.approvalStatus(toolName: "get_weather", callID: "call-other") == nil)
    }

    @Test
    func deferredTopLevelRejectionMessageKeepsBareNameLookup() {
        var context = RunContext<Void>()
        let deferredItem = ToolApprovalItem(
            toolName: "get_weather",
            callID: "call-weather",
            arguments: [:],
            tool: .function(ToolDescriptor(
                name: "get_weather",
                description: "Get weather.",
                deferLoading: true
            )),
            toolNamespace: "get_weather",
            allowBareNameAlias: true,
            toolLookupKey: .deferredTopLevel("get_weather")
        )

        context.rejectTool(deferredItem, rejectionMessage: "weather denied")

        #expect(context.rejectionMessage(toolName: "get_weather", callID: "call-weather") == "weather denied")
    }

    @Test
    func deferredTopLevelPermanentApprovalDoesNotAliasToBareName() {
        var context = RunContext<Void>()
        let deferredItem = ToolApprovalItem(
            toolName: "get_weather",
            callID: "call-weather",
            arguments: [:],
            tool: .function(ToolDescriptor(
                name: "get_weather",
                description: "Get weather.",
                deferLoading: true
            )),
            toolNamespace: "get_weather",
            allowBareNameAlias: true,
            toolLookupKey: .deferredTopLevel("get_weather")
        )

        context.approveTool(deferredItem, alwaysApprove: true)

        #expect(context.approvalStatus(toolName: "get_weather", callID: "call-weather-2") == nil)
        #expect(context.approvals["deferred_top_level:get_weather"]?.alwaysApproved == true)
        #expect(context.approvalStatus(
            toolName: "get_weather",
            callID: "call-weather-2",
            toolNamespace: "get_weather",
            existingPending: deferredItem,
            toolLookupKey: .deferredTopLevel("get_weather")
        ) == true)
    }

    @Test
    func deferredTopLevelLegacyPermanentApprovalKeyStillRestores() {
        let deferredItem = ToolApprovalItem(
            toolName: "get_weather",
            callID: "call-weather",
            arguments: [:],
            tool: .function(ToolDescriptor(
                name: "get_weather",
                description: "Get weather.",
                deferLoading: true
            )),
            toolNamespace: "get_weather",
            allowBareNameAlias: true,
            toolLookupKey: .deferredTopLevel("get_weather")
        )
        let context = RunContext<Void>(
            approvals: [
                "get_weather.get_weather": ToolApprovalRecord(alwaysApproved: true)
            ]
        )

        #expect(context.approvalStatus(
            toolName: "get_weather",
            callID: "call-weather-2",
            toolNamespace: "get_weather",
            existingPending: deferredItem,
            toolLookupKey: .deferredTopLevel("get_weather")
        ) == true)
    }
}
