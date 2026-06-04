import AppIntents

struct ShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickRecordIntent(),
            phrases: ["用 \(.applicationName) 记录"],
            shortTitle: "快速记录",
            systemImageName: "pencil"
        )
    }
}
