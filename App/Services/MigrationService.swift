import Foundation
import SwiftData

actor MigrationService {
    static let shared = MigrationService()

    private init() {}

    func migrateIfNeeded(container: ModelContainer) async {
        let hasMigrated = UserDefaults.standard.bool(forKey: "memory_migration_completed")
        guard !hasMigrated else { return }

        let context = ModelContext(container)
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
