import Testing
import ClinDeskAgents

@Suite
struct FunctionToolOutputTests {
    @Test
    func structuredToolOutputsArePreservedForModelInput() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_media", name: "media", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Received."))
            ])
        ])
        let media = FunctionTool<Void>(name: "media", description: "Return media.") { _, _ in
            .structured([
                .text("hello"),
                .image(ToolOutputImage(
                    fileID: "file_img",
                    detail: .high
                )),
                .file(ToolOutputFileContent(
                    fileData: "ZmFrZQ==",
                    filename: "note.txt"
                ))
            ])
        }
        let agent = Agent<Void>(name: "Assistant", tools: [media], model: model)

        let result = try await Runner.run(agent: agent, input: "Run")

        let expectedOutput: JSONValue = [
            [
                "type": "input_text",
                "text": "hello"
            ],
            [
                "type": "input_image",
                "file_id": "file_img",
                "detail": "high"
            ],
            [
                "type": "input_file",
                "file_data": "ZmFrZQ==",
                "filename": "note.txt"
            ]
        ]
        #expect(result.finalOutput == "Received.")
        #expect(result.newItems.contains(.functionCallOutput(FunctionCallOutput(
            callID: "call_media",
            output: expectedOutput
        ))))
    }

    @Test
    func structuredImageToolOutputRequiresImageURLOrFileID() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_image", name: "image", arguments: [:]))
            ])
        ])
        let image = FunctionTool<Void>(
            name: "image",
            description: "Return an image.",
            failureErrorFunction: nil
        ) { _, _ in
            .structured([.image(ToolOutputImage())])
        }
        let agent = Agent<Void>(name: "Assistant", tools: [image], model: model)

        await #expect(throws: AgentsError.invalidToolOutput(
            "At least one of image_url or file_id must be provided."
        )) {
            _ = try await Runner.run(agent: agent, input: "Run")
        }
    }

    @Test
    func structuredFileToolOutputValidationUsesDefaultFailureFormatter() async throws {
        let model = FakeModel([
            ModelResponse(output: [
                .functionCall(FunctionCall(callID: "call_file", name: "file", arguments: [:]))
            ]),
            ModelResponse(output: [
                .message(AgentMessage(role: .assistant, content: "Recovered."))
            ])
        ])
        let file = FunctionTool<Void>(name: "file", description: "Return a file.") { _, _ in
            .structured([.file(ToolOutputFileContent())])
        }
        let agent = Agent<Void>(name: "Assistant", tools: [file], model: model)

        let result = try await Runner.run(agent: agent, input: "Run")

        #expect(result.finalOutput == "Recovered.")
        let requests = await model.requests()
        #expect(requests.dropFirst().first?.input.contains {
            if case .functionCallOutput(let output) = $0 {
                return output.callID == "call_file"
                    && output.output.stringValue == "An error occurred while running the tool. Please try again. Error: Invalid tool output: At least one of file_data, file_url, or file_id must be provided."
            }
            return false
        } == true)
    }
}
