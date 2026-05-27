import Foundation

public enum HandoffFilters {
    public static func nestHandoffHistory<Context: Sendable>(
        _ handoffInputData: HandoffInputData<Context>,
        historyMapper: HandoffHistoryMapper? = nil
    ) async throws -> HandoffInputData<Context> {
        try await HandoffHistory.nestHandoffHistory(
            handoffInputData,
            historyMapper: historyMapper
        )
    }

    public static func defaultHandoffHistoryMapper(
        _ transcript: [ModelInputItem]
    ) -> [ModelInputItem] {
        HandoffHistory.defaultHandoffHistoryMapper(transcript)
    }

    public static func removeAllTools<Context: Sendable>(
        _ handoffInputData: HandoffInputData<Context>
    ) async -> HandoffInputData<Context> {
        handoffInputData.clone(
            inputHistory: removeTools(from: handoffInputData.inputHistory),
            preHandoffItems: removeTools(from: handoffInputData.preHandoffItems),
            newItems: removeTools(from: handoffInputData.newItems),
            inputItems: handoffInputData.inputItems.map(removeTools(from:))
        )
    }

    public static func removeTools(from items: [ModelInputItem]) -> [ModelInputItem] {
        items.filter { !isToolItem($0) }
    }

    public static func isToolItem(_ item: ModelInputItem) -> Bool {
        switch item {
        case .functionCall,
                .functionCallOutput,
                .customToolCall,
                .customToolCallOutput,
                .computerCall,
                .computerCallOutput,
                .localShellCall,
                .localShellCallOutput,
                .shellCall,
                .shellCallOutput,
                .applyPatchCall,
                .applyPatchCallOutput,
                .reasoning:
            return true
        case .raw(let value):
            guard let type = value["type"]?.stringValue else {
                return false
            }
            return toolItemTypes.contains(type)
        case .message,
                .refusal:
            return false
        }
    }

    private static let toolItemTypes: Set<String> = [
        "function_call",
        "function_call_output",
        "computer_call",
        "computer_call_output",
        "reasoning",
        "local_shell_call",
        "local_shell_call_output",
        "shell_call",
        "shell_call_output",
        "apply_patch_call",
        "apply_patch_call_output",
        "custom_tool_call",
        "custom_tool_call_output"
    ]
}
