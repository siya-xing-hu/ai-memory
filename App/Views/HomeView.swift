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
    @State private var store: DayChatStore?
    @State private var inputText = ""
    @State private var isRecording = false
    @State private var showCalendar = false
    @State private var showSettings = false
    @State private var icebreakerMessage: String? = nil

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

            await store?.summarizePendingDayChats()
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
                    isLoading: store.isLoading
                )
            }
            .navigationTitle("AI Memory")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showCalendar = true }) {
                        Image(systemName: "calendar")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showCalendar) {
                CalendarView(store: store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
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

        if messages.isEmpty, let icebreaker = icebreakerMessage {
            let icebreakerMessage = ChatMessage(role: .ai, content: icebreaker)
            messages.append(icebreakerMessage)
        }

        return messages
    }

    private func sendMessage(store: DayChatStore) {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        store.addUserMessage(content: text)

        Task {
            await store.triggerAIResponse()
        }
    }
}
