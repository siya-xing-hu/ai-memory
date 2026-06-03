import Foundation

actor AIService {
    static let shared = AIService()
    private var provider: LLMProvider?

    private init() {}

    func configure(apiKey: String, model: LLMChatModel, baseURL: String? = nil) {
        let config = LLMConfig(apiKey: apiKey, baseURL: baseURL, model: model.rawValue)
        provider = UnifiedLLMProvider(config: config, type: model.provider)
    }

    func isConfigured() -> Bool {
        provider != nil
    }

    func process(content: String) async throws -> (summary: String, tags: [String]) {
        guard let provider else {
            throw LLMError.noConfig
        }

        let prompt = """
        请分析以下用户记录的内容，生成摘要和标签。

        内容：\(content)

        要求：
        1. 摘要：用一句话概括核心信息，不超过30字
        2. 标签：提取2-5个关键词标签

        请严格按以下JSON格式输出，不要添加任何其他内容：
        {"summary": "摘要内容", "tags": ["标签1", "标签2"]}
        """

        let response = try await provider.chat(messages: [
            LLMChatMessage(role: "system", content: "你是一个信息整理助手，擅长提取摘要和关键词。只输出JSON格式。"),
            LLMChatMessage(role: "user", content: prompt)
        ])

        return try parseResponse(response)
    }

    func generateDailyReview(memories: [Memory]) async throws -> String {
        guard let provider else {
            throw LLMError.noConfig
        }

        let contents = memories.map { "- \($0.summary)" }.joined(separator: "\n")
        let prompt = """
        请根据今日记录生成一份回顾总结。

        今日记录：
        \(contents)

        请用中文输出，按类别分组，简洁明了。
        """

        return try await provider.chat(messages: [
            LLMChatMessage(role: "system", content: "你是一个生活记录回顾助手。"),
            LLMChatMessage(role: "user", content: prompt)
        ])
    }

    private func parseResponse(_ response: String) throws -> (summary: String, tags: [String]) {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["summary"] as? String,
              let tags = json["tags"] as? [String] else {
            return (summary: cleaned.prefix(30).description, tags: [])
        }
        return (summary: summary, tags: tags)
    }
}
