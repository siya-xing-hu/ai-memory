import Foundation

actor EmbeddingService {
    static let shared = EmbeddingService()
    private(set) var provider: LLMProvider?

    private init() {}

    func configure(apiKey: String, model: LLMEmbeddingModel = .bigModel, baseURL: String? = nil) {
        let config = LLMConfig(apiKey: apiKey, baseURL: baseURL, model: model.rawValue)
        provider = UnifiedLLMProvider(config: config, type: model.provider)
    }

    func embed(text: String) async throws -> [Double] {
        guard let provider else {
            throw LLMError.noConfig
        }
        return try await provider.embed(text: text)
    }

    nonisolated func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).map(*).reduce(0, +)
        let normA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let normB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}
