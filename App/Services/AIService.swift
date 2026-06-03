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

    // MARK: - Icebreaker

    func generateIcebreaker(context: [TopicSummary]) async throws -> String {
        guard let provider else {
            throw LLMError.noConfig
        }

        let contextText = context.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n")

        let prompt = """
        生成一句简短的引导，帮用户打开话匣子。

        历史相关记忆：
        \(contextText.isEmpty ? "（无相关历史数据）" : contextText)

        规则：
        - 只提 1 个方向，不超过 2 句话
        - 不要强行关联，无相关数据时用通用开场
        - 是引导不是建议，不替用户决定该做什么
        - 语气像朋友聊天
        """

        return try await provider.chat(messages: [
            LLMChatMessage(role: "system", content: "你是一个生活记录助手，帮用户打开话匣子。只输出引导语，不输出其他内容。"),
            LLMChatMessage(role: "user", content: prompt)
        ])
    }

    // MARK: - Batched Response

    func generateResponse(messages: [ChatMessage], context: [TopicSummary]?) async throws -> String {
        guard let provider else {
            throw LLMError.noConfig
        }

        let userMessages = messages
            .filter { $0.role == .user }
            .map { "- [\(timeString($0.createdAt))] \($0.content)" }
            .joined(separator: "\n")

        let contextText = context?.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n") ?? ""

        let prompt = """
        你是一个思维发散助手，帮助用户整理和延伸思路。
        你绝对不能提供知识性回答。你的任务是：
        1. 通过提问帮助用户理清自己的思路
        2. 把用户当前的想法和他过去记录中的相关话题联系起来
        3. 引导用户深入思考同一话题的层次

        规则：
        - 不回答"怎么做"类问题，而是反问"为什么想做"或"之前是否接触过"
        - 每次回复只提 1-2 个相关问题，保持简洁（50字以内）
        - 如果用户只是记录事实（无提问），帮他联系历史记忆或提示遗漏角度
        - 语气像朋友聊天，不要像老师讲课

        \(contextText.isEmpty ? "" : "\n相关历史记忆：\n" + contextText)

        用户今日记录：
        \(userMessages)
        """

        return try await provider.chat(messages: [
            LLMChatMessage(role: "system", content: "你是一个思维发散助手。只输出回复内容，不输出其他。"),
            LLMChatMessage(role: "user", content: prompt)
        ])
    }

    // MARK: - Summarization

    func summarize(dayChat: DayChat) async throws -> [TopicSummary] {
        guard let provider else {
            throw LLMError.noConfig
        }

        let allMessages = dayChat.messages
            .map { "[\($0.role == .user ? "用户" : "AI")] \($0.content)" }
            .joined(separator: "\n")

        let prompt = """
        你是一个忠实记录助手。你需要阅读一天内的对话记录，按话题整理用户的记忆。

        【内容判定原则】
        - 只有用户明确表达、确认或补充的内容才能进入记忆
        - AI 的提问如果没有得到用户的进一步展开，不纳入记忆
        - 必须直接引用或近似复述用户原文，不得推测、扩写、补全

        【关键事实保留规则】
        汇总的 summary 字段必须显式包含用户消息中出现的：
        - 时间（日期、星期、时段、截止日、纪念日等）
        - 地点（城市、场所、具体位置）
        - 人物（名字、关系）
        - 职业/工作信息（公司、项目、职位）
        - 个人偏好（喜好、习惯、价值观）
        - 承诺/计划/事件
        - 数字/金额/量化信息

        宁可冗长也不要丢失这些事实。如果用户原文已包含完整事实，直接引用原文是最安全的做法。

        对话记录：
        \(allMessages)

        请严格按以下 JSON 格式输出，不要添加任何其他内容：
        [{"title": "话题标题", "summary": "基于用户原文的概要", "citedMessageIds": ["消息ID1", "消息ID2"], "aiContextIds": ["AI消息ID1"]}]
        """

        let response = try await provider.chat(messages: [
            LLMChatMessage(role: "system", content: "你是一个忠实记录助手，擅长整理和归类。只输出 JSON 格式。"),
            LLMChatMessage(role: "user", content: prompt)
        ])

        return try parseSummaryResponse(response, dayChatDate: dayChat.date)
    }

    // MARK: - Legacy Methods (kept for compatibility during migration)

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

    func generateDailyReview(dayChat: DayChat) async throws -> String {
        guard let provider else {
            throw LLMError.noConfig
        }

        let contents = dayChat.messages
            .filter { $0.role == .user }
            .map { "- \($0.content)" }
            .joined(separator: "\n")
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

    // MARK: - Parsing

    private func parseSummaryResponse(_ response: String, dayChatDate: Date) throws -> [TopicSummary] {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [TopicSummary(
                dayChatDate: dayChatDate,
                title: "今日记录",
                summary: cleaned.prefix(200).description,
                citedMessageIds: []
            )]
        }

        return jsonArray.compactMap { dict -> TopicSummary? in
            guard let title = dict["title"] as? String,
                  let summary = dict["summary"] as? String else {
                return nil
            }
            let citedIds = (dict["citedMessageIds"] as? [String])?.compactMap(UUID.init) ?? []
            let aiIds = (dict["aiContextIds"] as? [String])?.compactMap(UUID.init) ?? []
            return TopicSummary(
                dayChatDate: dayChatDate,
                title: title,
                summary: summary,
                citedMessageIds: citedIds,
                aiContextIds: aiIds
            )
        }
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

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
