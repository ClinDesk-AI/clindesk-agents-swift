import Foundation

public enum DefaultModels {
    public static let defaultModelEnvironmentVariableName = "CLINDESK_AGENTS_DEFAULT_MODEL"
    public static let fallbackModelName = "local"

    public static func defaultModel(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        (environment[defaultModelEnvironmentVariableName] ?? fallbackModelName).lowercased()
    }

    public static func defaultModelSettings(
        model: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ModelSettings {
        ModelSettings()
    }
}
