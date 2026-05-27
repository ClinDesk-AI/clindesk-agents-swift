import Foundation

public func trace(
    _ workflowName: String,
    traceID: String? = nil,
    groupID: String? = nil,
    metadata: [String: JSONValue]? = nil,
    disabled: Bool = false
) async -> Trace {
    await (await getTraceProvider()).createTrace(
        name: workflowName,
        traceID: traceID,
        groupID: groupID,
        metadata: metadata,
        disabled: disabled
    )
}

public func getCurrentTrace() -> Trace? {
    TracingScope.getCurrentTrace()
}

public func getCurrentSpan() -> Span? {
    TracingScope.getCurrentSpan()
}

public func agentSpan(
    name: String,
    handoffs: [String]? = nil,
    tools: [String]? = nil,
    outputType: String? = nil,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: AgentSpanData(name: name, handoffs: handoffs, tools: tools, outputType: outputType),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func taskSpan(
    name: String,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: TaskSpanData(name: name),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func turnSpan(
    turn: Int,
    agentName: String,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: TurnSpanData(turn: turn, agentName: agentName),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func functionSpan(
    name: String,
    input: String? = nil,
    output: String? = nil,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: FunctionSpanData(name: name, input: input, output: output),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func generationSpan(
    input: [[String: JSONValue]]? = nil,
    output: [[String: JSONValue]]? = nil,
    model: String? = nil,
    modelConfig: [String: JSONValue]? = nil,
    usage: [String: JSONValue]? = nil,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: GenerationSpanData(
            input: input,
            output: output,
            model: model,
            modelConfig: modelConfig,
            usage: usage
        ),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func responseSpan(
    responseID: String? = nil,
    input: JSONValue? = nil,
    usage: [String: JSONValue]? = nil,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: ResponseSpanData(responseID: responseID, input: input, usage: usage),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func handoffSpan(
    fromAgent: String? = nil,
    toAgent: String? = nil,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: HandoffSpanData(fromAgent: fromAgent, toAgent: toAgent),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func customSpan(
    name: String,
    data: [String: JSONValue] = [:],
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: CustomSpanData(name: name, data: data),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func guardrailSpan(
    name: String,
    triggered: Bool = false,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: GuardrailSpanData(name: name, triggered: triggered),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func transcriptionSpan(
    model: String? = nil,
    input: String? = nil,
    inputFormat: String? = "pcm",
    output: String? = nil,
    modelConfig: [String: JSONValue]? = nil,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: TranscriptionSpanData(
            input: input,
            inputFormat: inputFormat,
            output: output,
            model: model,
            modelConfig: modelConfig
        ),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func speechSpan(
    model: String? = nil,
    input: String? = nil,
    output: String? = nil,
    outputFormat: String? = "pcm",
    modelConfig: [String: JSONValue]? = nil,
    firstContentAt: String? = nil,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: SpeechSpanData(
            input: input,
            output: output,
            outputFormat: outputFormat,
            model: model,
            modelConfig: modelConfig,
            firstContentAt: firstContentAt
        ),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}

public func speechGroupSpan(
    input: String? = nil,
    spanID: String? = nil,
    parent: SpanParent? = nil,
    disabled: Bool = false
) async -> Span {
    await (await getTraceProvider()).createSpan(
        spanData: SpeechGroupSpanData(input: input),
        spanID: spanID,
        parent: parent,
        disabled: disabled
    )
}
