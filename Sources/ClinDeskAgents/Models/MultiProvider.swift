import Foundation

public final class MultiProviderMap: @unchecked Sendable {
    private let lock = NSLock()
    private var mapping: [String: any ModelProvider]

    public init(_ mapping: [String: any ModelProvider] = [:]) {
        self.mapping = mapping
    }

    public func hasPrefix(_ prefix: String) -> Bool {
        lock.lock()
        let result = mapping[prefix] != nil
        lock.unlock()
        return result
    }

    public func getMapping() -> [String: any ModelProvider] {
        lock.lock()
        let result = mapping
        lock.unlock()
        return result
    }

    public func setMapping(_ mapping: [String: any ModelProvider]) {
        lock.lock()
        self.mapping = mapping
        lock.unlock()
    }

    public func provider(for prefix: String) -> (any ModelProvider)? {
        lock.lock()
        let provider = mapping[prefix]
        lock.unlock()
        return provider
    }

    public func addProvider(_ provider: any ModelProvider, for prefix: String) {
        lock.lock()
        mapping[prefix] = provider
        lock.unlock()
    }

    public func removeProvider(for prefix: String) {
        lock.lock()
        mapping.removeValue(forKey: prefix)
        lock.unlock()
    }
}

public enum MultiProviderUnknownPrefixMode: String, Codable, Equatable, Sendable {
    case error
    case modelID = "model_id"
}

public struct MultiProvider: ModelProvider {
    public var providerMap: MultiProviderMap
    public var defaultProvider: (any ModelProvider)?
    public var unknownPrefixMode: MultiProviderUnknownPrefixMode

    public init(
        providerMap: MultiProviderMap = MultiProviderMap(),
        defaultProvider: (any ModelProvider)? = nil,
        unknownPrefixMode: MultiProviderUnknownPrefixMode = .error
    ) {
        self.providerMap = providerMap
        self.defaultProvider = defaultProvider
        self.unknownPrefixMode = unknownPrefixMode
    }

    public func model(named name: String?) async throws -> any Model {
        guard let name, let slashIndex = name.firstIndex(of: "/") else {
            guard let defaultProvider else {
                throw AgentsError.modelNotFound(name ?? DefaultModels.defaultModel())
            }
            return try await defaultProvider.model(named: name)
        }

        let prefix = String(name[..<slashIndex])
        let strippedName = String(name[name.index(after: slashIndex)...])
        if let provider = providerMap.provider(for: prefix) {
            return try await provider.model(named: strippedName)
        }

        switch unknownPrefixMode {
        case .error:
            throw AgentsError.modelNotFound(name)
        case .modelID:
            guard let defaultProvider else {
                throw AgentsError.modelNotFound(name)
            }
            return try await defaultProvider.model(named: name)
        }
    }

    public func close() async {
        var providers = providerMap.getMapping().map(\.value)
        if let defaultProvider {
            providers.append(defaultProvider)
        }

        for provider in providers {
            await provider.close()
        }
    }
}
