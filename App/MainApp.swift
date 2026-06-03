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
        let createdContainer: ModelContainer
        do {
            createdContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
        container = createdContainer

        Task {
            await MigrationService.shared.migrateIfNeeded(container: createdContainer)
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
