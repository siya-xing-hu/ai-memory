# Daily Chat-Style Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor AI Memory from per-entry recording to a daily chat interface with AI-assisted icebreakers, topic-grouped summaries, and topic-level embeddings.

**Architecture:** New SwiftData models (`DayChat`, `ChatMessage`, `TopicSummary`) replace the old `Memory` model. A `DayChatStore` manages chat persistence. `AIService` gains icebreaker, batched response, and summarization capabilities. The UI becomes a full-screen chat with a bottom input bar. Old `Memory` data is migrated on first launch.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, iOS 18

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `App/Models/ChatMessage.swift` | Create | SwiftData model for individual chat messages (user/ai) |
| `App/Models/DayChat.swift` | Create | SwiftData model grouping messages by day, tracking summary state |
| `App/Models/TopicSummary.swift` | Create | SwiftData model for AI-generated topic summaries with embedding |
| `App/Models/Memory.swift` | Delete (after migration) | Old per-entry model |
| `App/ViewModels/DayChatStore.swift` | Create | Observable store replacing MemoryStore |
| `App/ViewModels/MemoryStore.swift` | Delete (after migration) | Old store |
| `App/Services/AIService.swift` | Modify | Add icebreaker, batched response, summarization |
| `App/Services/EmbeddingService.swift` | Modify | Remove message-level embedding; keep topic-level |
| `App/Providers/LLMProvider.swift` | Modify | Rename `ChatMessage` struct to avoid collision with model |
| `App/Views/ChatMessageRow.swift` | Create | Message bubble view (user right, ai left) |
| `App/Views/ChatInputBar.swift` | Create | Bottom input bar with text, voice, AI trigger, send |
| `App/Views/ChatView.swift` | Create | Scrollable chat message list |
| `App/Views/HomeView.swift` | Modify | Full rewrite as chat-based home |
| `App/Views/TimelineView.swift` | Delete | Replaced by chat view |
| `App/Views/SearchView.swift` | Modify | Search by TopicSummary instead of Memory |
| `App/Views/SettingsView.swift` | Modify | Add conversation mode toggle |
| `App/MainApp.swift` | Modify | Update schema to include new models |
| `App/Views/DailyReviewView.swift` | Modify | Update to use DayChat/TopicSummary |

---

## Task 1: Rename LLM ChatMessage to avoid collision

**Files:**
- Modify: `App/Providers/LLMProvider.swift`

The new SwiftData model will be named `ChatMessage`. The existing struct in `LLMProvider.swift` must be renamed to prevent a name collision.

- [ ] **Step 1: Rename struct and update all references**

In `App/Providers/LLMProvider.swift`:

```swift
// OLD:
struct ChatMessage {
    let role: String
    let content: String
}

// NEW:
struct LLMChatMessage {
    let role: String
    let content: String
}
```

Update the `LLMProvider` protocol:

```swift
// OLD:
protocol LLMProvider: Sendable {
    func chat(messages: [ChatMessage]) async throws -> String
    func embed(text: String) async throws -> [Double]
}

// NEW:
protocol LLMProvider: Sendable {
    func chat(messages: [LLMChatMessage]) async throws -> String
    func embed(text: String) async throws -> [Double]
}
```

Update `UnifiedLLMProvider.customChat`:

```swift
// OLD:
private func customChat(messages: [ChatMessage]) async throws -> String {
    ...
    let chatMessages = messages.compactMap { msg -> [String: String]? in
        if msg.role == "system" {
            systemMessage = msg.content
            return nil
        }
        return ["role": msg.role == "user" ? "user" : "assistant", "content": msg.content]
    }
    ...
}

// NEW:
private func customChat(messages: [LLMChatMessage]) async throws -> String {
    ...
    let chatMessages = messages.compactMap { msg -> [String: String]? in
        if msg.role == "system" {
            systemMessage = msg.content
            return nil
        }
        return ["role": msg.role == "user" ? "user" : "assistant", "content": msg.content]
    }
    ...
}
```

- [ ] **Step 2: Update all references in AIService.swift**

In `App/Services/AIService.swift`, replace all `ChatMessage(` with `LLMChatMessage(`.

Example changes:

```swift
// OLD:
let response = try await provider.chat(messages: [
    ChatMessage(role: "system", content: "你是一个信息整理助手..."),
    ChatMessage(role: "user", content: prompt)
])

// NEW:
let response = try await provider.chat(messages: [
    LLMChatMessage(role: "system", content: "你是一个信息整理助手..."),
    LLMChatMessage(role: "user", content: prompt)
])
```

- [ ] **Step 3: Build to verify no compilation errors**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add App/Providers/LLMProvider.swift App/Services/AIService.swift
git commit -m "$(cat <<'EOF'
refactor: rename ChatMessage to LLMChatMessage in provider

Prevents name collision with the new SwiftData ChatMessage model.
EOF
)"
```

---

## Task 2: Create ChatMessage data model

**Files:**
- Create: `App/Models/ChatMessage.swift`

- [ ] **Step 1: Create the file**

Create `App/Models/ChatMessage.swift`:

```swift
import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case ai
}

@Model
class ChatMessage: @unchecked Sendable {
    var id: UUID
    var role: MessageRole
    var content: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add App/Models/ChatMessage.swift
git commit -m "feat: add ChatMessage SwiftData model"
```

---

## Task 3: Create DayChat data model

**Files:**
- Create: `App/Models/DayChat.swift`

- [ ] **Step 1: Create the file**

Create `App/Models/DayChat.swift`:

```swift
import Foundation
import SwiftData

@Model
class DayChat: @unchecked Sendable {
    @Attribute(.unique) var date: Date
    var messages: [ChatMessage]
    var summarizedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        date: Date,
        messages: [ChatMessage] = [],
        summarizedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.messages = messages
        self.summarizedAt = summarizedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add App/Models/DayChat.swift
git commit -m "feat: add DayChat SwiftData model"
```

---

## Task 4: Create TopicSummary data model

**Files:**
- Create: `App/Models/TopicSummary.swift`

- [ ] **Step 1: Create the file**

Create `App/Models/TopicSummary.swift`:

```swift
import Foundation
import SwiftData

@Model
class TopicSummary: @unchecked Sendable {
    var id: UUID
    var dayChatDate: Date
    var title: String
    var summary: String
    var citedMessageIds: [UUID]
    var aiContextIds: [UUID]
    var embedding: [Double]?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        dayChatDate: Date,
        title: String,
        summary: String,
        citedMessageIds: [UUID],
        aiContextIds: [UUID] = [],
        embedding: [Double]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.dayChatDate = dayChatDate
        self.title = title
        self.summary = summary
        self.citedMessageIds = citedMessageIds
        self.aiContextIds = aiContextIds
        self.embedding = embedding
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add App/Models/TopicSummary.swift
git commit -m "feat: add TopicSummary SwiftData model"
```

---

## Task 5: Update MainApp schema

**Files:**
- Modify: `App/MainApp.swift`
- Modify: `App/Models/Memory.swift` (add migration support)

- [ ] **Step 1: Update schema to include new models alongside old Memory**

In `App/MainApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct MainApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Memory.self, DayChat.self, ChatMessage.self, TopicSummary.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.com.app.memory")
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
        NotificationService.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .modelContainer(container)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds. May have warnings about unused types.

- [ ] **Step 3: Commit**

```bash
git add App/MainApp.swift
git commit -m "feat: add new models to SwiftData schema"
```

---

## Task 6: Create DayChatStore

**Files:**
- Create: `App/ViewModels/DayChatStore.swift`

- [ ] **Step 1: Create the file**

Create `App/ViewModels/DayChatStore.swift`:

```swift
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

        do {
            try modelContext.save()
        } catch {
            AppLogger.storage.error("Save AI message failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func messagesForToday() -> [ChatMessage] {
        currentDayChat?.messages ?? []
    }

    // MARK: - AI Response

    func triggerAIResponse(mode: ConversationMode) async {
        guard await AIService.shared.isConfigured() else { return }
        guard let chat = currentDayChat else { return }

        let pendingMessages = pendingUserMessages()
        guard !pendingMessages.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // Get context from historical topics
            let context = try await fetchRelatedContext(for: pendingMessages)
            let response = try await AIService.shared.generateResponse(
                messages: pendingMessages,
                context: context
            )
            await MainActor.run {
                addAIMessage(content: response)
            }
        } catch {
            AppLogger.ai.error("AI response failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "AI 回复失败"
        }
    }

    private func pendingUserMessages() -> [ChatMessage] {
        guard let chat = currentDayChat else { return [] }
        let messages = chat.messages
        // Find last AI message index
        var lastAIMessageIndex = -1
        for (index, message) in messages.enumerated().reversed() {
            if message.role == .ai {
                lastAIMessageIndex = index
                break
            }
        }
        // Return all user messages after last AI message
        return messages.enumerated()
            .filter { $0.offset > lastAIMessageIndex && $0.element.role == .user }
            .map { $0.element }
    }

    private func fetchRelatedContext(for messages: [ChatMessage]) async throws -> [TopicSummary] {
        // Simple keyword-based context retrieval for now
        let keywords = messages.flatMap { $0.content.split(separator: " ").map(String($0)) }
        let allTopics = try modelContext.fetch(FetchDescriptor<TopicSummary>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
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

                // Generate embedding
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
            // Don't mark as summarized so it retries next time
        }
    }

    // MARK: - Search

    func search(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        // Keyword search fallback (always available)
        let descriptor = FetchDescriptor<TopicSummary>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            let allTopics = try modelContext.fetch(descriptor)
            searchResults = allTopics.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.summary.localizedCaseInsensitiveContains(query)
            }
        } catch {
            AppLogger.storage.error("Search failed: \(error.localizedDescription, privacy: .public)")
        }

        // Semantic search if embedding is available
        if await EmbeddingService.shared.provider != nil {
            do {
                let queryEmbedding = try await EmbeddingService.shared.embed(text: query)
                let allTopics = try modelContext.fetch(descriptor)
                let scored = allTopics.compactMap { topic -> (topic: TopicSummary, score: Double)? in
                    guard let emb = topic.embedding else { return nil }
                    let score = EmbeddingService.shared.cosineSimilarity(queryEmbedding, emb)
                    return (topic, score)
                }
                let semanticResults = scored.sorted { $0.score > $1.score }
                    .filter { $0.score > 0.7 }
                    .map { $0.topic }

                // Merge and deduplicate
                let keywordSet = Set(searchResults.map { $0.id })
                for topic in semanticResults where !keywordSet.contains(topic.id) {
                    searchResults.append(topic)
                }
            } catch {
                AppLogger.embedding.error("Semantic search failed: \(error.localizedDescription, privacy: .public)")
            }
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

enum ConversationMode: String, CaseIterable, Identifiable {
    case batched = "batched"
    case interactive = "interactive"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .batched: return "批量响应"
        case .interactive: return "交互问答"
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds. `MemoryStore.swift` still exists but may show unused warnings.

- [ ] **Step 3: Commit**

```bash
git add App/ViewModels/DayChatStore.swift
git commit -m "$(cat <<'EOF'
feat: add DayChatStore with chat, summary, search, and review queries

Replaces MemoryStore. Manages DayChat lifecycle, batched AI responses,
auto-summarization, topic search, and historical context queries.
EOF
)"
```

---

## Task 7: Upgrade AIService

**Files:**
- Modify: `App/Services/AIService.swift`

- [ ] **Step 1: Add new methods to AIService**

Replace the entire contents of `App/Services/AIService.swift`:

```swift
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

    // MARK: - Parsing

    private func parseSummaryResponse(_ response: String, dayChatDate: Date) throws -> [TopicSummary] {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Fallback: treat entire response as a single topic
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
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add App/Services/AIService.swift
git commit -m "$(cat <<'EOF'
feat: add icebreaker, batched response, and summarization to AIService

- generateIcebreaker: creates context-aware opening prompts
- generateResponse: batched AI response with historical context
- summarize: topic-grouped daily summary with key fact preservation
EOF
)"
```

---

## Task 8: Create Chat UI Components

**Files:**
- Create: `App/Views/ChatMessageRow.swift`
- Create: `App/Views/ChatInputBar.swift`
- Create: `App/Views/ChatView.swift`

- [ ] **Step 1: Create ChatMessageRow.swift**

Create `App/Views/ChatMessageRow.swift`:

```swift
import SwiftUI

struct ChatMessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == .user ? Color.blue.opacity(0.15) : Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(16)

                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            if message.role == .ai {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.createdAt)
    }
}
```

- [ ] **Step 2: Create ChatInputBar.swift**

Create `App/Views/ChatInputBar.swift`:

```swift
import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onVoice: () -> Void
    let onTriggerAI: () -> Void
    let canTriggerAI: Bool
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(action: onVoice) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                        .frame(width: 36, height: 36)
                }

                TextField("记录点什么...", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)

                if canTriggerAI {
                    Button(action: onTriggerAI) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                            .frame(width: 36, height: 36)
                    }
                    .disabled(isLoading)
                }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(text.isEmpty ? .gray : .blue)
                }
                .disabled(text.isEmpty || isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }
}
```

- [ ] **Step 3: Create ChatView.swift**

Create `App/Views/ChatView.swift`:

```swift
import SwiftUI

struct ChatView: View {
    let messages: [ChatMessage]
    let isLoading: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(messages, id: \.id) { message in
                        ChatMessageRow(message: message)
                            .id(message.id)
                    }

                    if isLoading {
                        HStack {
                            Spacer(minLength: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("思考中...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray5))
                                .cornerRadius(16)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .id("loading-indicator")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isLoading) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let lastId = messages.last?.id {
                withAnimation {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            } else if isLoading {
                withAnimation {
                    proxy.scrollTo("loading-indicator", anchor: .bottom)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add App/Views/ChatMessageRow.swift App/Views/ChatInputBar.swift App/Views/ChatView.swift
git commit -m "feat: add Chat UI components (message row, input bar, chat list)"
```

---

## Task 9: Rewrite HomeView as Chat-Based Home

**Files:**
- Modify: `App/Views/HomeView.swift`

- [ ] **Step 1: Replace HomeView entirely**

Replace `App/Views/HomeView.swift` with:

```swift
import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("llm_api_key") private var chatApiKey = ""
    @AppStorage("llm_model") private var selectedChatModel = LLMChatModel.custom.rawValue
    @AppStorage("llm_base_url") private var chatBaseURL = ""
    @AppStorage("embedding_api_key") private var embeddingApiKey = ""
    @AppStorage("embedding_model") private var selectedEmbeddingModel = LLMEmbeddingModel.bigModel.rawValue
    @AppStorage("embedding_base_url") private var embeddingBaseURL = ""
    @AppStorage("conversation_mode") private var conversationModeRaw = ConversationMode.batched.rawValue
    @State private var store: DayChatStore?
    @State private var inputText = ""
    @State private var isRecording = false
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showDailyReview = false
    @State private var icebreakerMessage: String? = nil

    private var conversationMode: ConversationMode {
        ConversationMode(rawValue: conversationModeRaw) ?? .batched
    }

    var body: some View {
        Group {
            if let store = store {
                chatContent(store: store)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            store = DayChatStore(modelContext: modelContext)
            configureAIProviders()
        }
    }

    private func configureAIProviders() {
        Task {
            if !chatApiKey.isEmpty, let model = LLMChatModel(rawValue: selectedChatModel) {
                await AIService.shared.configure(
                    apiKey: chatApiKey,
                    model: model,
                    baseURL: chatBaseURL.isEmpty ? nil : chatBaseURL
                )
            }
            if !embeddingApiKey.isEmpty, let model = LLMEmbeddingModel(rawValue: selectedEmbeddingModel) {
                await EmbeddingService.shared.configure(
                    apiKey: embeddingApiKey,
                    model: model,
                    baseURL: embeddingBaseURL.isEmpty ? nil : embeddingBaseURL
                )
            }

            // Trigger auto-summarization for past days
            await store?.summarizePendingDayChats()

            // Generate icebreaker if today is empty
            await generateIcebreakerIfNeeded()
        }
    }

    private func generateIcebreakerIfNeeded() async {
        guard let store = store else { return }
        guard store.currentDayChat == nil || store.messagesForToday().isEmpty else { return }
        guard await AIService.shared.isConfigured() else { return }

        let context = store.topicSummariesForSameDayLastYear() +
                       store.topicSummariesForSameWeekday()

        do {
            let icebreaker = try await AIService.shared.generateIcebreaker(context: context)
            await MainActor.run {
                self.icebreakerMessage = icebreaker
            }
        } catch {
            AppLogger.ai.error("Icebreaker generation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func chatContent(store: DayChatStore) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                ChatView(
                    messages: effectiveMessages(store: store),
                    isLoading: store.isLoading
                )

                ChatInputBar(
                    text: $inputText,
                    onSend: { sendMessage(store: store) },
                    onVoice: { isRecording = true },
                    onTriggerAI: { triggerAI(store: store) },
                    canTriggerAI: conversationMode == .batched && hasPendingUserMessages(store: store),
                    isLoading: store.isLoading
                )
            }
            .navigationTitle("AI Memory")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showDailyReview = true }) {
                        Label("回顾", systemImage: "sparkles")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSearch = true }) {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchView(store: store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showDailyReview) {
                DailyReviewView(store: store)
            }
            .sheet(isPresented: $isRecording) {
                VoiceRecordView { text in
                    if !text.isEmpty {
                        inputText = text
                        sendMessage(store: store)
                    }
                }
            }
        }
    }

    private func effectiveMessages(store: DayChatStore) -> [ChatMessage] {
        var messages = store.messagesForToday()

        // Insert icebreaker if today is empty
        if messages.isEmpty, let icebreaker = icebreakerMessage {
            let icebreakerMessage = ChatMessage(role: .ai, content: icebreaker)
            messages.append(icebreakerMessage)
        }

        return messages
    }

    private func hasPendingUserMessages(store: DayChatStore) -> Bool {
        guard let chat = store.currentDayChat else { return false }
        let messages = chat.messages
        var lastAIMessageIndex = -1
        for (index, message) in messages.enumerated().reversed() {
            if message.role == .ai {
                lastAIMessageIndex = index
                break
            }
        }
        return messages.enumerated().contains { $0.offset > lastAIMessageIndex && $0.element.role == .user }
    }

    private func sendMessage(store: DayChatStore) {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        store.addUserMessage(content: text)

        if conversationMode == .interactive {
            Task {
                await store.triggerAIResponse(mode: .interactive)
            }
        }
    }

    private func triggerAI(store: DayChatStore) {
        Task {
            await store.triggerAIResponse(mode: .batched)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds. `TimelineView.swift` still exists but unused.

- [ ] **Step 3: Commit**

```bash
git add App/Views/HomeView.swift
git commit -m "$(cat <<'EOF'
feat: rewrite HomeView as chat-based interface

Replaces timeline view with full-screen chat. Supports icebreaker,
batched/interactive modes, and auto-summarization on launch.
EOF
)"
```

---

## Task 10: Update SearchView for TopicSummary Search

**Files:**
- Modify: `App/Views/SearchView.swift`

- [ ] **Step 1: Replace SearchView**

Replace `App/Views/SearchView.swift` with:

```swift
import SwiftUI

struct SearchView: View {
    let store: DayChatStore
    @State private var query = ""
    @State private var searchType: SearchType = .keyword
    @Environment(\.dismiss) private var dismiss

    enum SearchType {
        case keyword, semantic
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Picker("搜索方式", selection: $searchType) {
                    Text("关键词").tag(SearchType.keyword)
                    Text("语义").tag(SearchType.semantic)
                }
                .pickerStyle(.segmented)
                .padding()

                List(store.searchResults) { topic in
                    TopicRow(topic: topic)
                }
                .listStyle(.plain)
            }
            .navigationTitle("搜索记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索你的记忆...", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
        .onChange(of: query) { _, newValue in
            Task { @MainActor in
                await store.search(query: newValue)
            }
        }
    }
}

struct TopicRow: View {
    let topic: TopicSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text(topic.title)
                .font(.headline)
            Text(topic.summary)
                .font(.body)
                .lineLimit(3)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(topic.dayChatDate) {
            formatter.dateFormat = "今天 · MM月dd日"
        } else if Calendar.current.isDateInYesterday(topic.dayChatDate) {
            formatter.dateFormat = "昨天 · MM月dd日"
        } else {
            formatter.dateFormat = "yyyy年MM月dd日"
        }
        return formatter.string(from: topic.dayChatDate)
    }
}

extension TopicSummary: Identifiable {}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add App/Views/SearchView.swift
git commit -m "feat: update SearchView to search TopicSummary records"
```

---

## Task 11: Update DailyReviewView

**Files:**
- Modify: `App/Views/DailyReviewView.swift`

- [ ] **Step 1: Replace DailyReviewView**

Replace `App/Views/DailyReviewView.swift` with:

```swift
import SwiftUI

struct DailyReviewView: View {
    let store: DayChatStore
    @State private var reviewText = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        ProgressView("生成中...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if !reviewText.isEmpty {
                        Text(reviewText)
                            .font(.body)
                            .lineSpacing(6)
                    } else {
                        let topics = store.topicSummariesForDate(Date())
                        if topics.isEmpty {
                            Text("今日暂无汇总记录")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(topics) { topic in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(topic.title)
                                        .font(.headline)
                                    Text(topic.summary)
                                        .font(.body)
                                    Divider()
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("今日回顾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                generateReview()
            }
        }
    }

    private func generateReview() {
        let topics = store.topicSummariesForDate(Date())
        guard !topics.isEmpty else { return }
        isLoading = true
        Task {
            guard await AIService.shared.isConfigured() else {
                isLoading = false
                return
            }
            do {
                let contents = topics.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n")
                let prompt = """
                请根据今日话题汇总生成一份回顾总结。

                今日话题：
                \(contents)

                请用中文输出，按话题分组，简洁明了。
                """
                let review = try await AIService.shared.generateResponse(
                    messages: [ChatMessage(role: .user, content: prompt)],
                    context: nil
                )
                reviewText = review
                isLoading = false
            } catch {
                reviewText = "生成失败"
                isLoading = false
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add App/Views/DailyReviewView.swift
git commit -m "feat: update DailyReviewView to use TopicSummary data"
```

---

## Task 12: Update SettingsView with Conversation Mode

**Files:**
- Modify: `App/Views/SettingsView.swift`

- [ ] **Step 1: Add conversation mode toggle**

In `App/Views/SettingsView.swift`, add after the notification section:

```swift
// Find this existing Section("通知") block and add a new section after it:

Section("对话") {
    Picker("对话模式", selection: $conversationModeRaw) {
        ForEach(ConversationMode.allCases) { mode in
            Text(mode.displayName).tag(mode.rawValue)
        }
    }
    .pickerStyle(.segmented)
}

// Also add the @AppStorage property at the top:
@AppStorage("conversation_mode") private var conversationModeRaw = ConversationMode.batched.rawValue
```

The complete SettingsView.swift file should have these additions:

At the top, add:
```swift
@AppStorage("conversation_mode") private var conversationModeRaw = ConversationMode.batched.rawValue
```

After the notification section (around line 106), add:
```swift
Section("对话") {
    Picker("对话模式", selection: $conversationModeRaw) {
        ForEach(ConversationMode.allCases) { mode in
            Text(mode.displayName).tag(mode.rawValue)
        }
    }
    .pickerStyle(.segmented)
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add App/Views/SettingsView.swift
git commit -m "feat: add conversation mode toggle to settings"
```

---

## Task 13: Add Migration from Old Memory Data

**Files:**
- Modify: `App/MainApp.swift`
- Create: `App/Services/MigrationService.swift`

Migration must run before old files are deleted, because `MigrationService` references the old `Memory` model.

- [ ] **Step 1: Create MigrationService**

Create `App/Services/MigrationService.swift`:

```swift
import Foundation
import SwiftData

actor MigrationService {
    static let shared = MigrationService()

    private init() {}

    func migrateIfNeeded(context: ModelContext) async {
        let hasMigrated = UserDefaults.standard.bool(forKey: "memory_migration_completed")
        guard !hasMigrated else { return }

        let descriptor = FetchDescriptor<Memory>(sortBy: [SortDescriptor(\.createdAt)])
        do {
            let oldMemories = try context.fetch(descriptor)
            guard !oldMemories.isEmpty else {
                UserDefaults.standard.set(true, forKey: "memory_migration_completed")
                return
            }

            AppLogger.storage.info("Starting migration. oldMemories=\(oldMemories.count)")

            let calendar = Calendar.current
            let grouped = Dictionary(grouping: oldMemories) { memory in
                calendar.startOfDay(for: memory.createdAt)
            }

            for (date, memories) in grouped {
                let messages = memories.map { old in
                    ChatMessage(
                        role: .user,
                        content: old.content,
                        createdAt: old.createdAt
                    )
                }

                let dayChat = DayChat(
                    date: date,
                    messages: messages,
                    summarizedAt: nil
                )
                context.insert(dayChat)
            }

            try context.save()
            UserDefaults.standard.set(true, forKey: "memory_migration_completed")
            AppLogger.storage.info("Migration complete. migratedDays=\(grouped.count)")
        } catch {
            AppLogger.storage.error("Migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 2: Call migration in MainApp (keep Memory in schema)**

Keep `Memory.self` in the schema so migration can read old data.

`App/MainApp.swift` init should already have Memory in the schema from Task 5. Add the migration call:

```swift
init() {
    let schema = Schema([Memory.self, DayChat.self, ChatMessage.self, TopicSummary.self])
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        groupContainer: .identifier("group.com.app.memory")
    )
    do {
        container = try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError("Could not initialize ModelContainer: \(error)")
    }

    Task {
        await MigrationService.shared.migrateIfNeeded(context: container.mainContext)
    }

    NotificationService.shared.requestAuthorization()
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add App/Services/MigrationService.swift App/MainApp.swift
git commit -m "feat: add migration from old Memory to DayChat"
```

---

## Task 14: Delete Legacy Files (After Migration Confirmed)

**Files:**
- Delete: `App/Models/Memory.swift`
- Delete: `App/ViewModels/MemoryStore.swift`
- Delete: `App/Views/TimelineView.swift`
- Delete: `App/Services/MigrationService.swift`
- Modify: `App/MainApp.swift`

> **Note:** Only execute this task after confirming migration works on real devices. `MigrationService` references `Memory`, so both must be deleted together.

- [ ] **Step 1: Remove legacy files**

```bash
git rm App/Models/Memory.swift App/ViewModels/MemoryStore.swift App/Views/TimelineView.swift App/Services/MigrationService.swift
```

- [ ] **Step 2: Remove Memory from schema and remove migration call**

Update `App/MainApp.swift`:

```swift
// Remove the migration Task block entirely. Final init:
init() {
    let schema = Schema([DayChat.self, ChatMessage.self, TopicSummary.self])
    let config = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        groupContainer: .identifier("group.com.app.memory")
    )
    do {
        container = try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError("Could not initialize ModelContainer: \(error)")
    }
    NotificationService.shared.requestAuthorization()
}
```

- [ ] **Step 3: Build to verify clean compile**

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds with no warnings about unused types.

- [ ] **Step 4: Commit**

```bash
git add App/MainApp.swift
git commit -m "chore: remove legacy Memory model, MemoryStore, TimelineView, and MigrationService"
```

Run: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add App/Services/MigrationService.swift App/MainApp.swift
git commit -m "$(cat <<'EOF'
feat: add migration service for old Memory -> DayChat conversion

Groups old Memory entries by day into DayChat records, marking them
for re-summarization. Uses UserDefaults flag to prevent re-runs.
EOF
)"
```

---

## Self-Review

### Spec Coverage Check

| Spec Section | Plan Task | Status |
|-------------|-----------|--------|
| Data model: ChatMessage | Task 2 | ✅ |
| Data model: DayChat | Task 3 | ✅ |
| Data model: TopicSummary | Task 4 | ✅ |
| DayChat.date = startOfDay | Task 3 | ✅ |
| DayChat.summarizedAt | Task 3 | ✅ |
| ChatMessage no embedding | Task 2 | ✅ |
| DayChatStore: loadTodayChat | Task 6 | ✅ |
| DayChatStore: addUserMessage | Task 6 | ✅ |
| DayChatStore: addAIMessage | Task 6 | ✅ |
| DayChatStore: triggerAIResponse (batched) | Task 6 | ✅ |
| DayChatStore: summarizePendingDayChats | Task 6 | ✅ |
| DayChatStore: search (keyword + semantic) | Task 6 | ✅ |
| DayChatStore: topicSummariesForDate | Task 6 | ✅ |
| DayChatStore: topicSummariesForSameDayLastYear | Task 6 | ✅ |
| DayChatStore: topicSummariesForSameWeekday | Task 6 | ✅ |
| AIService: generateIcebreaker | Task 7 | ✅ |
| AIService: generateResponse (batched) | Task 7 | ✅ |
| AIService: summarize (with key facts) | Task 7 | ✅ |
| HomeView: full-screen chat | Task 9 | ✅ |
| HomeView: icebreaker (UI only, no DB) | Task 9 | ✅ |
| HomeView: batched mode | Task 9 | ✅ |
| HomeView: interactive mode | Task 9 | ✅ |
| ChatInputBar: voice, text, AI trigger, send | Task 8 | ✅ |
| SearchView: TopicSummary search | Task 10 | ✅ |
| SettingsView: conversation mode | Task 12 | ✅ |
| Migration: old Memory -> DayChat | Task 14 | ✅ |
| Delete old files | Task 13 | ✅ |

### Placeholder Scan

- No "TBD", "TODO", "implement later"
- No vague error handling descriptions
- Every function body is complete
- Every step has exact file path and code

### Type Consistency Check

- `ChatMessage` (model) defined in Task 2, used consistently in Task 6, 7, 8, 9
- `DayChat` defined in Task 3, used consistently
- `TopicSummary` defined in Task 4, used consistently
- `LLMChatMessage` renamed in Task 1, used consistently in Task 7
- `ConversationMode` defined in Task 6, used in Task 9, 12
- `DayChatStore` defined in Task 6, used in Task 9, 10, 11

All types consistent across tasks.

---

## Verification Steps

After completing all tasks, verify the app:

1. **Build**: `xcodebuild -project "AI Memory.xcodeproj" -scheme "AI Memory" -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16' build`
   - Expected: Clean build, zero errors

2. **Fresh install test**:
   - Delete app from simulator
   - Install fresh
   - Open app: should show AI icebreaker
   - Type a message: should appear on right
   - Click AI button: should get AI response on left
   - Type more, click AI again: should get another response

3. **Mode B test**:
   - Go to Settings, switch to "交互问答"
   - Type a message: should auto-trigger AI response

4. **Search test**:
   - After having some records, use search
   - Should find topics by keyword

5. **Migration test** (if old data exists):
   - Install old version, add some memories
   - Install new version
   - Old memories should appear as DayChat entries
   - Old Memory records should no longer be queried
