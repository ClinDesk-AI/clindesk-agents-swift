import Foundation

extension RunnerLoop {
    func executeComputerToolRun(
        _ run: ComputerToolRun<Context>,
        agent: Agent<Context>,
        context: RunContext<Context>,
        parentSpan: Span? = nil
    ) async throws -> ComputerRunResult {
        var span = await functionSpan(
            name: run.tool.traceName,
            input: config.traceIncludeSensitiveData ? computerTraceInput(run.call) : nil,
            parent: parentSpan.map(SpanParent.span),
            disabled: config.tracingDisabled
        )
        await startRunSpan(&span)

        do {
            guard let computer = run.tool.computer else {
                throw AgentsError.invalidRunConfig("ComputerTool requires a computer instance to execute calls.")
            }
            let acknowledged = try await acknowledgeComputerSafetyChecks(
                call: run.call,
                tool: run.tool,
                agent: agent,
                context: context
            )
            let hookContext = ToolHookContext(
                runContext: context,
                toolName: run.tool.name,
                toolCallID: run.call.callID,
                toolInput: computerTracePayload(run.call)
            )
            try await callToolStartHooks(context: hookContext, agent: agent, tool: .computer(run.tool))
            let screenshot = try await executeComputerActions(run.call.effectiveActions, computer: computer)
            let imageURL = screenshot.isEmpty ? "" : "data:image/png;base64,\(screenshot)"
            if var data = span.spanData as? FunctionSpanData {
                data.output = config.traceIncludeSensitiveData ? imageURL : nil
                span.spanData = data
            }
            try await callToolEndHooks(
                context: hookContext,
                agent: agent,
                tool: .computer(run.tool),
                output: imageURL
            )
            await finishRunSpan(&span)
            return ComputerRunResult(
                call: run.call,
                imageURL: imageURL,
                acknowledgedSafetyChecks: acknowledged
            )
        } catch {
            await finishRunSpan(&span, error: error, toolName: run.tool.traceName)
            throw error
        }
    }

    private func computerTraceInput(_ call: ComputerCall) -> String? {
        computerTracePayload(call)?.prettyPrinted()
    }

    private func computerTracePayload(_ call: ComputerCall) -> JSONValue? {
        let actions = call.effectiveActions
        guard !actions.isEmpty else {
            return nil
        }
        if actions.count == 1, let action = actions.first {
            return (try? JSONValue.encoded(action)) ?? .emptyObject
        }
        return JSONValue.array(actions.map { (try? JSONValue.encoded($0)) ?? .emptyObject })
    }

    private func acknowledgeComputerSafetyChecks(
        call: ComputerCall,
        tool: ComputerTool<Context>,
        agent: Agent<Context>,
        context: RunContext<Context>
    ) async throws -> [PendingComputerSafetyCheck]? {
        guard !call.pendingSafetyChecks.isEmpty,
              let onSafetyCheck = tool.onSafetyCheck
        else {
            return nil
        }

        var acknowledged: [PendingComputerSafetyCheck] = []
        for check in call.pendingSafetyChecks {
            let accepted = try await onSafetyCheck(ComputerToolSafetyCheckData(
                context: context,
                agent: agent,
                toolCall: call,
                safetyCheck: check
            ))
            guard accepted else {
                throw AgentsError.invalidRunConfig("Computer tool safety check was not acknowledged.")
            }
            acknowledged.append(check)
        }
        return acknowledged
    }

    private func executeComputerActions(
        _ actions: [ComputerAction],
        computer: any Computer
    ) async throws -> String {
        var lastActionWasScreenshot = false
        var lastScreenshot = ""
        for action in actions {
            lastActionWasScreenshot = false
            switch action.type {
            case "click":
                try await computer.click(
                    x: try required(action.x, "x", action: action.type),
                    y: try required(action.y, "y", action: action.type),
                    button: try required(action.button, "button", action: action.type),
                    keys: action.keys
                )
            case "double_click":
                try await computer.doubleClick(
                    x: try required(action.x, "x", action: action.type),
                    y: try required(action.y, "y", action: action.type),
                    keys: action.keys
                )
            case "drag":
                try await computer.drag(
                    path: try required(action.path, "path", action: action.type),
                    keys: action.keys
                )
            case "keypress":
                try await computer.keypress(try required(action.keys, "keys", action: action.type))
            case "move":
                try await computer.move(
                    x: try required(action.x, "x", action: action.type),
                    y: try required(action.y, "y", action: action.type),
                    keys: action.keys
                )
            case "screenshot":
                lastScreenshot = try await computer.screenshot()
                lastActionWasScreenshot = true
            case "scroll":
                try await computer.scroll(
                    x: try required(action.x, "x", action: action.type),
                    y: try required(action.y, "y", action: action.type),
                    scrollX: try required(action.scrollX, "scroll_x", action: action.type),
                    scrollY: try required(action.scrollY, "scroll_y", action: action.type),
                    keys: action.keys
                )
            case "type":
                try await computer.type(try required(action.text, "text", action: action.type))
            case "wait":
                try await computer.wait()
            default:
                throw AgentsError.invalidModelResponse(
                    "Computer tool returned unknown action type '\(action.type)'."
                )
            }
        }

        if lastActionWasScreenshot {
            return lastScreenshot
        }
        return try await computer.screenshot()
    }

    private func required<Value>(_ value: Value?, _ field: String, action: String) throws -> Value {
        guard let value else {
            throw AgentsError.invalidModelResponse(
                "Computer action '\(action)' is missing required field '\(field)'."
            )
        }
        return value
    }
}
