import Foundation

public enum DebugOptions {
    public static let dontLogModelDataEnvironmentVariableName = "CLINDESK_AGENTS_DONT_LOG_MODEL_DATA"
    public static let dontLogToolDataEnvironmentVariableName = "CLINDESK_AGENTS_DONT_LOG_TOOL_DATA"

    public static func debugFlagEnabled(
        _ name: String,
        default defaultValue: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let value = environment[name] else {
            return defaultValue
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "1" || normalized == "true"
    }

    public static func dontLogModelData(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        debugFlagEnabled(
            dontLogModelDataEnvironmentVariableName,
            default: true,
            environment: environment
        )
    }

    public static func dontLogToolData(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        debugFlagEnabled(
            dontLogToolDataEnvironmentVariableName,
            default: true,
            environment: environment
        )
    }
}
