import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ai-memory"

    static let ai = Logger(subsystem: subsystem, category: "AI")
    static let embedding = Logger(subsystem: subsystem, category: "Embedding")
    static let storage = Logger(subsystem: subsystem, category: "Storage")
}

enum LLMChatModel: String, CaseIterable, Identifiable {
    case custom = "multi-kimi-k2.6"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .custom: return "multi-kimi-k2.6"
        }
    }

    var provider: LLMProviderType {
        switch self {
        case .custom: return .custom
        }
    }
}

enum LLMEmbeddingModel: String, CaseIterable, Identifiable {
    case bigModel = "embedding-3"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bigModel: return "embedding-3"
        }
    }

    var provider: LLMProviderType {
        switch self {
        case .bigModel: return .bigModel
        }
    }
}

enum LLMProviderType: String, CaseIterable {
    case custom = "Custom"
    case bigModel = "BigModel"
}

struct LLMConfig: Codable {
    var apiKey: String
    var baseURL: String?
    var model: String
}

protocol LLMProvider: Sendable {
    func chat(messages: [LLMChatMessage]) async throws -> String
    func embed(text: String) async throws -> [Double]
}

struct LLMChatMessage {
    let role: String
    let content: String
}

enum LLMResponseParser {
    static func chatText(from data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let choices = json?["choices"] as? [[String: Any]],
           let first = choices.first {
            if let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
            if let text = first["text"] as? String {
                return text
            }
        }

        if let content = json?["content"] as? String {
            return content
        }

        if let content = json?["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text
        }

        throw LLMError.invalidResponse
    }
}

actor UnifiedLLMProvider: LLMProvider {
    private let config: LLMConfig
    private let type: LLMProviderType
    private let urlSession: URLSession

    init(config: LLMConfig, type: LLMProviderType) {
        self.config = config
        self.type = type
        self.urlSession = URLSession.shared
    }

    func chat(messages: [LLMChatMessage]) async throws -> String {
        switch type {
        case .custom:
            return try await customChat(messages: messages)
        case .bigModel:
            throw LLMError.invalidConfig("BigModel provider only supports embeddings")
        }
    }

    func embed(text: String) async throws -> [Double] {
        switch type {
        case .custom:
            throw LLMError.invalidConfig("Custom provider only supports chat")
        case .bigModel:
            return try await bigModelEmbed(text: text)
        }
    }

    private func bigModelEmbed(text: String) async throws -> [Double] {
        let endpoint = config.baseURL ?? "https://open.bigmodel.cn/api/paas/v4/embeddings"
        guard let url = URL(string: endpoint) else {
            AppLogger.embedding.error("Invalid embedding endpoint: \(endpoint, privacy: .public)")
            throw LLMError.invalidConfig("URL 格式不正确")
        }
        AppLogger.embedding.info("Embedding request started. model=\(self.config.model, privacy: .public), textLength=\(text.count)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "input": text,
            "model": config.model
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = Self.truncatedBody(from: data)
            AppLogger.embedding.error("Embedding request failed. statusCode=\(statusCode), body=\(responseBody, privacy: .public)")
            throw LLMError.apiError(responseBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let embedData = json?["data"] as? [[String: Any]],
              let first = embedData.first,
              let embedding = first["embedding"] as? [Double] else {
            let responseBody = Self.truncatedBody(from: data)
            AppLogger.embedding.error("Embedding response parse failed. body=\(responseBody, privacy: .public)")
            throw LLMError.invalidResponse
        }
        AppLogger.embedding.info("Embedding request succeeded. dimensions=\(embedding.count)")
        return embedding
    }

    private func customChat(messages: [LLMChatMessage]) async throws -> String {
        let baseURL = config.baseURL ?? "https://token-hub.pinpula.com"
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            AppLogger.ai.error("Invalid chat endpoint. baseURL=\(baseURL, privacy: .public)")
            throw LLMError.invalidConfig("URL 格式不正确")
        }
        AppLogger.ai.info("Chat request started. model=\(self.config.model, privacy: .public), messagesCount=\(messages.count)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var systemMessage: String?
        let chatMessages = messages.compactMap { msg -> [String: String]? in
            if msg.role == "system" {
                systemMessage = msg.content
                return nil
            }
            return ["role": msg.role == "user" ? "user" : "assistant", "content": msg.content]
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": chatMessages,
            "max_tokens": 4096,
            "temperature": 0.3
        ]
        if let system = systemMessage {
            body["system"] = system
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = Self.truncatedBody(from: data)
            AppLogger.ai.error("Chat request failed. statusCode=\(statusCode), body=\(responseBody, privacy: .public)")
            throw LLMError.apiError(responseBody)
        }

        do {
            let text = try LLMResponseParser.chatText(from: data)
            AppLogger.ai.info("Chat request succeeded. responseLength=\(text.count)")
            return text
        } catch {
            let responseBody = Self.truncatedBody(from: data)
            AppLogger.ai.error("Chat response parse failed. error=\(error.localizedDescription, privacy: .public), body=\(responseBody, privacy: .public)")
            throw error
        }
    }

    private static func truncatedBody(from data: Data) -> String {
        let body = String(data: data, encoding: .utf8) ?? "Unknown"
        return String(body.prefix(2_000))
    }
}

enum LLMError: Error, LocalizedError {
    case apiError(String)
    case invalidConfig(String)
    case invalidResponse
    case noConfig

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "API Error: \(msg)"
        case .invalidConfig(let msg): return msg
        case .invalidResponse: return "Invalid response"
        case .noConfig: return "No LLM config found"
        }
    }
}
