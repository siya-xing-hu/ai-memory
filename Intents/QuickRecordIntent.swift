import AppIntents
import SwiftData

struct QuickRecordIntent: AppIntent {
    static let title: LocalizedStringResource = "快速记录"
    static let description = IntentDescription("快速记录一条内容到 AI Memory")

    @Parameter(title: "内容", requestValueDialog: "要记录什么？")
    var content: String

    func perform() async throws -> some IntentResult {
        let schema = Schema([DayChat.self, ChatMessage.self, TopicSummary.self])
        let config = ModelConfiguration(
            schema: schema,
            groupContainer: .identifier("group.com.app.memory")
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DayChat>(
            predicate: #Predicate { $0.date == today }
        )
        let dayChat: DayChat
        if let existing = try context.fetch(descriptor).first {
            dayChat = existing
        } else {
            dayChat = DayChat(date: today)
            context.insert(dayChat)
        }

        let message = ChatMessage(role: .user, content: content)
        context.insert(message)
        dayChat.messages.append(message)
        dayChat.updatedAt = Date()

        try context.save()

        return .result(dialog: "已记录")
    }
}

struct QuickVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "语音记录"
    static let description = IntentDescription("通过语音记录到 AI Memory")

    func perform() async throws -> some IntentResult {
        return .result(dialog: "请打开应用进行语音记录")
    }
}
