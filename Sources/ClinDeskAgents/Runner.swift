import Foundation

open class AgentRunner: @unchecked Sendable {
    public init() {}

    open func run<Context: Sendable>(
        agent: Agent<Context>,
        input: [ModelInputItem],
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) async throws -> RunResult {
        var resolvedConfig = runConfig
        if let maxTurns {
            resolvedConfig.maxTurns = maxTurns
        }
        if let hooks {
            resolvedConfig.hooks = hooks
        }
        if let session {
            resolvedConfig.session = session
        }
        let loop = RunnerLoop(
            startingAgent: agent,
            input: input,
            contextValue: context,
            modelProvider: modelProvider,
            config: resolvedConfig
        )
        return try await loop.run()
    }

    open func run<Context: Sendable>(state: RunState<Context>) async throws -> RunResult {
        let loop = RunnerLoop(resumeState: state)
        return try await loop.run()
    }

    open func runStream<Context: Sendable>(
        agent: Agent<Context>,
        input: String,
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) -> AsyncThrowingStream<RunStreamEvent<Context>, Error> {
        runStreamed(
            agent: agent,
            input: input,
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            session: session
        ).streamEvents()
    }

    open func runStreamed<Context: Sendable>(
        agent: Agent<Context>,
        input: String,
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) -> RunResultStreaming<Context> {
        runStreamed(
            agent: agent,
            input: [.message(AgentMessage(role: .user, content: input))],
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            session: session
        )
    }

    open func runStreamed<Context: Sendable>(
        agent: Agent<Context>,
        input: [ModelInputItem],
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) -> RunResultStreaming<Context> {
        let result = RunResultStreaming(
            input: input,
            currentAgent: agent,
            maxTurns: maxTurns ?? runConfig.maxTurns
        )
        let taskBox = StreamTaskBox()
        let stream = AsyncThrowingStream<RunStreamEvent<Context>, Error> { continuation in
            var config = runConfig
            let previousHandler = config.streamEventHandler
            if let maxTurns {
                config.maxTurns = maxTurns
            }
            if let hooks {
                config.hooks = hooks
            }
            if let session {
                config.session = session
            }
            let baseHooks = config.hooks
            let inputGuardrailNames = Set(
                agent.inputGuardrails.map(\.name) + config.inputGuardrails.map(\.name)
            )
            config.hooks = RunHooks(
                onLLMStart: baseHooks.onLLMStart,
                onLLMEnd: baseHooks.onLLMEnd,
                onAgentStart: baseHooks.onAgentStart,
                onAgentEnd: baseHooks.onAgentEnd,
                onHandoff: baseHooks.onHandoff,
                onToolStart: baseHooks.onToolStart,
                onToolEnd: baseHooks.onToolEnd,
                onGuardrail: { name, output in
                    if inputGuardrailNames.contains(name) {
                        result.recordInputGuardrailResult(InputGuardrailResult(
                            guardrailName: name,
                            output: output
                        ))
                    }
                    try await baseHooks.onGuardrail(name, output)
                }
            )
            config.streamEventHandler = { event in
                await previousHandler?(event)
                result.record(event.event)
                continuation.yield(event.event)
            }
            let task = Task {
                do {
                    let completed = try await self.run(
                        agent: agent,
                        input: input,
                        context: context,
                        modelProvider: modelProvider,
                        runConfig: config
                    )
                    result.finish(completed)
                    continuation.finish()
                } catch {
                    result.fail(error)
                    continuation.finish(throwing: error)
                }
            }
            taskBox.set(task)
            continuation.onTermination = { @Sendable _ in
                taskBox.cancel()
            }
        }
        result.attach(stream: stream, task: taskBox.task)
        return result
    }
}

private final class StreamTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTask: Task<Void, Never>?

    var task: Task<Void, Never>? {
        lock.lock()
        let value = storedTask
        lock.unlock()
        return value
    }

    func set(_ task: Task<Void, Never>) {
        lock.lock()
        storedTask = task
        lock.unlock()
    }

    func cancel() {
        task?.cancel()
    }
}

private final class DefaultAgentRunnerStore: @unchecked Sendable {
    private let lock = NSLock()
    private var runner = AgentRunner()

    func set(_ runner: AgentRunner?) {
        lock.lock()
        self.runner = runner ?? AgentRunner()
        lock.unlock()
    }

    func get() -> AgentRunner {
        lock.lock()
        let current = runner
        lock.unlock()
        return current
    }
}

public enum Runner {
    private static let defaultRunnerStore = DefaultAgentRunnerStore()

    public static func setDefaultAgentRunner(_ runner: AgentRunner? = nil) {
        defaultRunnerStore.set(runner)
    }

    public static func getDefaultAgentRunner() -> AgentRunner {
        defaultRunnerStore.get()
    }

    public static func run<Context: Sendable, Output: Decodable & Sendable>(
        agent: Agent<Context>,
        input: String,
        outputType: Output.Type,
        outputSchema: JSONValue? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) async throws -> TypedRunResult<Output> {
        try await run(
            agent: agent,
            input: [.message(AgentMessage(role: .user, content: input))],
            outputType: outputType,
            outputSchema: outputSchema,
            decoder: decoder,
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            session: session
        )
    }

    public static func run<Context: Sendable, Output: Decodable & Sendable>(
        agent: Agent<Context>,
        input: [ModelInputItem],
        outputType: Output.Type,
        outputSchema: JSONValue? = nil,
        decoder: JSONDecoder = JSONDecoder(),
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) async throws -> TypedRunResult<Output> {
        let agentOutputSchema = try outputSchema.map {
            try AgentOutputSchema(
                name: String(describing: outputType),
                jsonSchema: $0,
                strictJSONSchema: true
            )
        }
        let configuredAgent = agentOutputSchema.map {
            agent.clone(outputSchema: $0).withPublicAgent(agent)
        } ?? agent
        let result = try await run(
            agent: configuredAgent,
            input: input,
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            session: session
        )
        let decoded = try (agentOutputSchema?.validateJSON(
            outputType,
            jsonString: result.finalOutput,
            decoder: decoder
        ) ?? StructuredOutput.decode(outputType, from: result.finalOutput, decoder: decoder))
        return TypedRunResult(
            input: result.input,
            finalOutput: decoded,
            rawFinalOutput: result.finalOutput,
            lastAgentName: result.lastAgentName,
            lastAgent: result.lastAgent,
            trace: result.trace,
            newItems: result.newItems,
            modelResponses: result.modelResponses,
            usage: result.usage,
            responseID: result.responseID,
            inputGuardrailResults: result.inputGuardrailResults,
            outputGuardrailResults: result.outputGuardrailResults,
            toolInputGuardrailResults: result.toolInputGuardrailResults,
            toolOutputGuardrailResults: result.toolOutputGuardrailResults,
            interruptions: result.interruptions,
            agentToolInvocation: result.agentToolInvocation,
            modelInputItems: result.modelInputItems,
            replayFromModelInputItems: result.replayFromModelInputItems
        )
    }

    public static func run<Context: Sendable>(
        agent: Agent<Context>,
        input: String,
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) async throws -> RunResult {
        try await run(
            agent: agent,
            input: [.message(AgentMessage(role: .user, content: input))],
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            session: session
        )
    }

    public static func run<Context: Sendable>(
        agent: Agent<Context>,
        input: [ModelInputItem],
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) async throws -> RunResult {
        try await getDefaultAgentRunner().run(
            agent: agent,
            input: input,
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            session: session
        )
    }

    public static func run<Context: Sendable>(state: RunState<Context>) async throws -> RunResult {
        try await getDefaultAgentRunner().run(state: state)
    }

    public static func runStream<Context: Sendable>(
        agent: Agent<Context>,
        input: String,
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) -> AsyncThrowingStream<RunStreamEvent<Context>, Error> {
        getDefaultAgentRunner().runStream(
            agent: agent,
            input: input,
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            session: session
        )
    }

    public static func runStreamed<Context: Sendable>(
        agent: Agent<Context>,
        input: String,
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) -> RunResultStreaming<Context> {
        getDefaultAgentRunner().runStreamed(
            agent: agent,
            input: input,
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            session: session
        )
    }

    public static func runStreamed<Context: Sendable>(
        agent: Agent<Context>,
        input: [ModelInputItem],
        context: Context? = nil,
        maxTurns: Int? = nil,
        hooks: RunHooks<Context>? = nil,
        modelProvider: (any ModelProvider)? = nil,
        runConfig: RunConfig<Context> = RunConfig(),
        session: (any Session)? = nil
    ) -> RunResultStreaming<Context> {
        getDefaultAgentRunner().runStreamed(
            agent: agent,
            input: input,
            context: context,
            maxTurns: maxTurns,
            hooks: hooks,
            modelProvider: modelProvider,
            runConfig: runConfig,
            session: session
        )
    }
}
