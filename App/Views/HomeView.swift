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
