import Foundation

public enum ToolErrorUtils {
    public static let redactedToolErrorMessage = "Tool execution failed. Error details are redacted."

    public static func traceToolError(
        traceIncludeSensitiveData: Bool,
        errorMessage: String
    ) -> String {
        traceIncludeSensitiveData ? errorMessage : redactedToolErrorMessage
    }
}
