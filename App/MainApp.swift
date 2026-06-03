import SwiftUI
import SwiftData

@main
struct MainApp: App {
    let container: ModelContainer

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

    var body: some Scene {
        WindowGroup {
            HomeView()
                .modelContainer(container)
        }
    }
}
