import CryptoKit
import Foundation

public let promptCacheKeyField = "prompt_cache_key"

struct PromptCacheKeyResolver<Context: Sendable>: Sendable {
    var generatedKey: String?

    init(runState: RunState<Context>?) {
        self.generatedKey = runState?.generatedPromptCacheKey
    }

    mutating func resolve(
        modelSettings: ModelSettings,
        model: any Model,
        session: (any Session)?,
        groupID: String?
    ) -> String? {
        guard !modelSettings.hasPromptCacheKey else {
            return nil
        }
        guard model.supportsDefaultPromptCacheKey else {
            return nil
        }
        if let generatedKey {
            return generatedKey
        }

        let grouping = RunGroupingResolver.resolve(session: session, groupID: groupID)
        let key = Self.promptCacheKey(for: grouping)
        generatedKey = key
        return key
    }

    static func modelSettingsWithPromptCacheKey(
        _ modelSettings: ModelSettings,
        promptCacheKey: String?
    ) -> ModelSettings {
        guard let promptCacheKey, !modelSettings.hasPromptCacheKey else {
            return modelSettings
        }
        var extraArgs = modelSettings.extraArgs ?? [:]
        extraArgs[promptCacheKeyField] = .string(promptCacheKey)
        var copy = modelSettings
        copy.extraArgs = extraArgs
        return copy
    }

    private static func promptCacheKey(for grouping: RunGrouping) -> String {
        switch grouping.kind {
        case .run:
            return "agents-sdk:run:\(grouping.value)"
        case .conversation, .session, .group:
            return hashedKey(kind: grouping.kind.rawValue, value: grouping.value)
        }
    }

    private static func hashedKey(kind: String, value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        return "agents-sdk:\(kind):\(hex)"
    }
}

extension ModelSettings {
    var hasPromptCacheKey: Bool {
        extraArgs?[promptCacheKeyField] != nil
    }
}
