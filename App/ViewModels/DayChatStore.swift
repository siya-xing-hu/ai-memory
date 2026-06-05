import Foundation
import SwiftData
import SwiftUI
import Observation

@Observable
class DayChatStore: @unchecked Sendable {
    private let modelContext: ModelContext
    var currentDayChat: DayChat?
    var searchResults: [TopicSummary] = []
    var isLoading = false
    var errorMessage: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadTodayChat()
    }

    // MARK: - DayChat Management

    func loadTodayChat() {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DayChat>(
            predicate: #Predicate { $0.date == today }
        )
        do {
            currentDayChat = try modelContext.fetch(descriptor).first
        } catch {
            AppLogger.storage.error("Load today chat failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "加载失败"
        }
    }

    func dayChat(for date: Date) -> DayChat? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DayChat>(
            predicate: #Predicate { $0.date == startOfDay }
        )
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            AppLogger.storage.error("Fetch day chat failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func dayChatExists(for date: Date) -> Bool {
        dayChat(for: date) != nil
    }

    func datesWithChats() -> Set<Date> {
        let descriptor = FetchDescriptor<DayChat>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        do {
            let chats = try modelContext.fetch(descriptor)
            return Set(chats.map { $0.date })
        } catch {
            AppLogger.storage.error("Fetch dates with chats failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Messages

    func addUserMessage(content: String) {
        let today = Calendar.current.startOfDay(for: Date())
        let chat: DayChat
        if let existing = currentDayChat {
            chat = existing
        } else {
            chat = DayChat(date: today)
            modelContext.insert(chat)
            currentDayChat = chat
        }

        let message = ChatMessage(role: .user, content: content)
        chat.messages.append(message)
        chat.updatedAt = Date()
        currentDayChat = chat

        do {
            try modelContext.save()
            AppLogger.storage.info("User message saved. messageCount=\(chat.messages.count)")
        } catch {
            AppLogger.storage.error("Save user message failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "保存失败"
        }
    }

    func addAIMessage(content: String) {
        guard let chat = currentDayChat else { return }
        let message = ChatMessage(role: .ai, content: content)
        chat.messages.append(message)
        chat.updatedAt = Date()
        currentDayChat = chat

        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Save AI message failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func messagesForToday() -> [ChatMessage] {
        currentDayChat?.messages.sorted(by: { $0.createdAt < $1.createdAt }) ?? []
    }

    // MARK: - AI Response

    @MainActor
    func triggerAIResponse() async {
        AppLogger.ai.info("triggerAIResponse started")
        guard await AIService.shared.isConfigured() else {
            AppLogger.ai.error("AI not configured, skipping response")
            return
        }
        guard let chat = currentDayChat else {
            AppLogger.ai.error("currentDayChat is nil, skipping response")
            return
        }

        let pendingMessages = pendingUserMessages()
        AppLogger.ai.info("pendingMessages count=\(pendingMessages.count)")
        guard !pendingMessages.isEmpty else {
            AppLogger.ai.error("pendingMessages is empty, skipping response")
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Create empty AI message immediately for streaming
        let aiMessage = ChatMessage(role: .ai, content: "")
        chat.messages.append(aiMessage)
        chat.updatedAt = Date()
        currentDayChat = chat
        try? modelContext.save()
        AppLogger.ai.info("Empty AI message created and saved")

        do {
            let context = try await fetchRelatedContext(for: pendingMessages)
            AppLogger.ai.info("Fetched related context count=\(context.count)")
            let conversationHistory = Array(chat.messages.dropLast())
            AppLogger.ai.info("Conversation history count=\(conversationHistory.count)")
            let stream = await AIService.shared.generateStream(
                messages: conversationHistory,
                context: context
            )
            AppLogger.ai.info("Stream created, starting consumption")
            var fullText = ""
            var chunkCount = 0
            for try await chunk in stream {
                chunkCount += 1
                fullText += chunk
                aiMessage.content = fullText
                chat.updatedAt = Date()
                currentDayChat = chat
                try? modelContext.save()
                AppLogger.ai.info("Received chunk #\(chunkCount), length=\(chunk.count), total=\(fullText.count)")
            }
            AppLogger.ai.info("Stream consumption complete. chunks=\(chunkCount), totalLength=\(fullText.count)")
        } catch {
            AppLogger.ai.error("AI response failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "AI 回复失败"
            aiMessage.content = "AI 回复失败"
            chat.updatedAt = Date()
            currentDayChat = chat
            try? modelContext.save()
        }
    }

    private func pendingUserMessages() -> [ChatMessage] {
        guard let chat = currentDayChat else {
            AppLogger.ai.error("pendingUserMessages: currentDayChat is nil")
            return []
        }
        let messages = chat.messages
        AppLogger.ai.info("pendingUserMessages: total messages count=\(messages.count)")
        for (i, m) in messages.enumerated() {
            AppLogger.ai.info("  [\(i)] role=\(m.role.rawValue), content=\(m.content.prefix(30))")
        }
        var lastAIMessageIndex = -1
        for (index, message) in messages.enumerated().reversed() {
            if message.role == .ai {
                lastAIMessageIndex = index
                break
            }
        }
        AppLogger.ai.info("pendingUserMessages: lastAIMessageIndex=\(lastAIMessageIndex)")
        let result = messages.enumerated()
            .filter { $0.offset > lastAIMessageIndex && $0.element.role == .user }
            .map { $0.element }
        AppLogger.ai.info("pendingUserMessages: result count=\(result.count)")
        return result
    }

    private func fetchRelatedContext(for messages: [ChatMessage]) async throws -> [TopicSummary] {
        let keywords = messages.flatMap { $0.content.split(separator: " ").map { String($0) } }
        let descriptor = FetchDescriptor<TopicSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let allTopics = try modelContext.fetch(descriptor)
        return allTopics.filter { topic in
            keywords.contains { keyword in
                topic.title.localizedCaseInsensitiveContains(keyword) ||
                topic.summary.localizedCaseInsensitiveContains(keyword)
            }
        }.prefix(3).map { $0 }
    }

    // MARK: - Summarization

    func summarizePendingDayChats() async {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DayChat>(
            predicate: #Predicate { $0.date < today && $0.summarizedAt == nil }
        )
        do {
            let pending = try modelContext.fetch(descriptor)
            for dayChat in pending {
                await summarize(dayChat: dayChat)
            }
        } catch {
            AppLogger.storage.error("Fetch pending day chats failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func summarize(dayChat: DayChat) async {
        guard await AIService.shared.isConfigured() else { return }
        guard !dayChat.messages.isEmpty else {
            dayChat.summarizedAt = Date()
            try? modelContext.save()
            return
        }

        do {
            AppLogger.ai.info("Summarizing dayChat. date=\(dayChat.date), messages=\(dayChat.messages.count)")
            let topics = try await AIService.shared.summarize(dayChat: dayChat)

            for topic in topics {
                modelContext.insert(topic)

                if await EmbeddingService.shared.provider != nil {
                    do {
                        let embedText = topic.title + "\n" + topic.summary
                        topic.embedding = try await EmbeddingService.shared.embed(text: embedText)
                    } catch {
                        AppLogger.embedding.error("Topic embedding failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            dayChat.summarizedAt = Date()
            try modelContext.save()
            AppLogger.ai.info("Summarization complete. topics=\(topics.count)")
        } catch {
            AppLogger.ai.error("Summarization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Search

    func search(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        let descriptor = FetchDescriptor<TopicSummary>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        if await EmbeddingService.shared.provider != nil {
            do {
                let queryEmbedding = try await EmbeddingService.shared.embed(text: query)
                let allTopics = try modelContext.fetch(descriptor)
                let scored = allTopics.compactMap { topic -> (topic: TopicSummary, score: Double)? in
                    guard let emb = topic.embedding else { return nil }
                    let score = EmbeddingService.shared.cosineSimilarity(queryEmbedding, emb)
                    return (topic, score)
                }
                searchResults = scored.sorted { $0.score > $1.score }
                    .prefix(10)
                    .map { $0.topic }
                return
            } catch {
                AppLogger.embedding.error("Semantic search failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            let allTopics = try modelContext.fetch(descriptor)
            searchResults = Array(allTopics.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.summary.localizedCaseInsensitiveContains(query)
            }.prefix(10))
        } catch {
            AppLogger.storage.error("Search failed: \(error.localizedDescription, privacy: .public)")
            searchResults = []
        }
    }

    // MARK: - Topic Queries

    func topicSummariesForDate(_ date: Date) -> [TopicSummary] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<TopicSummary>(
            predicate: #Predicate { $0.dayChatDate == startOfDay }
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            AppLogger.storage.error("Fetch topics for date failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func topicSummariesForSameDayLastYear() -> [TopicSummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayComponents = calendar.dateComponents([.month, .day], from: today)

        let descriptor = FetchDescriptor<TopicSummary>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            let allTopics = try modelContext.fetch(descriptor)
            return allTopics.filter { topic in
                let topicComponents = calendar.dateComponents([.month, .day], from: topic.dayChatDate)
                return topicComponents.month == todayComponents.month &&
                       topicComponents.day == todayComponents.day &&
                       topic.dayChatDate != today
            }
        } catch {
            return []
        }
    }

    func topicSummariesForSameWeekday() -> [TopicSummary] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)

        let descriptor = FetchDescriptor<TopicSummary>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            let allTopics = try modelContext.fetch(descriptor)
            return allTopics.filter { topic in
                calendar.component(.weekday, from: topic.dayChatDate) == weekday &&
                topic.dayChatDate != today
            }
        } catch {
            return []
        }
    }
}
