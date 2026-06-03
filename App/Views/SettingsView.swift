import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("llm_api_key") private var chatApiKey = ""
    @AppStorage("llm_model") private var selectedChatModel = LLMChatModel.custom.rawValue
    @AppStorage("llm_base_url") private var chatBaseURL = ""
    @AppStorage("embedding_api_key") private var embeddingApiKey = ""
    @AppStorage("embedding_model") private var selectedEmbeddingModel = LLMEmbeddingModel.bigModel.rawValue
    @AppStorage("embedding_base_url") private var embeddingBaseURL = ""
    @AppStorage("daily_reminder_enabled") private var reminderEnabled = true
    @AppStorage("daily_review_enabled") private var reviewEnabled = true
    @AppStorage("conversation_mode") private var conversationModeRaw = ConversationMode.batched.rawValue
    @State private var chatTestResult: String?
    @State private var embeddingTestResult: String?
    @State private var isTestingChat = false
    @State private var isTestingEmbedding = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Chat 配置") {
                    Picker("模型", selection: $selectedChatModel) {
                        ForEach(LLMChatModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }

                    SecureField("Chat API Key", text: $chatApiKey)

                    TextField("Chat Base URL（可选）", text: $chatBaseURL)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: testChatConnection) {
                        HStack {
                            Text("测试 Chat")
                            if isTestingChat {
                                ProgressView()
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .disabled(chatApiKey.isEmpty || isTestingChat)

                    if let result = chatTestResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("成功") ? .green : .red)
                    }
                }

                Section("Embedding 配置") {
                    Picker("模型", selection: $selectedEmbeddingModel) {
                        ForEach(LLMEmbeddingModel.allCases) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }

                    SecureField("Embedding API Key", text: $embeddingApiKey)

                    TextField("Embedding Base URL（可选）", text: $embeddingBaseURL)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: testEmbeddingConnection) {
                        HStack {
                            Text("测试 Embedding")
                            if isTestingEmbedding {
                                ProgressView()
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .disabled(embeddingApiKey.isEmpty || isTestingEmbedding)

                    if let result = embeddingTestResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("成功") ? .green : .red)
                    }
                }

                Section("通知") {
                    Toggle("每日记录提醒", isOn: $reminderEnabled)
                    Toggle("每日回顾", isOn: $reviewEnabled)
                }
                .onChange(of: reminderEnabled) { _, enabled in
                    if enabled {
                        NotificationService.shared.scheduleDailyReminder()
                    } else {
                        NotificationService.shared.cancelAll()
                        if reviewEnabled {
                            NotificationService.shared.scheduleDailyReview()
                        }
                    }
                }
                .onChange(of: reviewEnabled) { _, enabled in
                    if enabled {
                        NotificationService.shared.scheduleDailyReview()
                    } else {
                        NotificationService.shared.cancelAll()
                        if reminderEnabled {
                            NotificationService.shared.scheduleDailyReminder()
                        }
                    }
                }

                Section("对话") {
                    Picker("对话模式", selection: $conversationModeRaw) {
                        ForEach(ConversationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        saveConfig()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveConfig() {
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
        }
        if reminderEnabled {
            NotificationService.shared.scheduleDailyReminder()
        }
        if reviewEnabled {
            NotificationService.shared.scheduleDailyReview()
        }
    }

    private func testChatConnection() {
        guard let model = LLMChatModel(rawValue: selectedChatModel) else { return }
        isTestingChat = true
        chatTestResult = nil
        Task {
            await AIService.shared.configure(
                apiKey: chatApiKey,
                model: model,
                baseURL: chatBaseURL.isEmpty ? nil : chatBaseURL
            )
            do {
                _ = try await AIService.shared.process(content: "你好")
                await MainActor.run {
                    chatTestResult = "Chat 连接成功"
                    isTestingChat = false
                }
            } catch {
                await MainActor.run {
                    chatTestResult = "Chat 连接失败: \(error.localizedDescription)"
                    isTestingChat = false
                }
            }
        }
    }

    private func testEmbeddingConnection() {
        guard let model = LLMEmbeddingModel(rawValue: selectedEmbeddingModel) else { return }
        isTestingEmbedding = true
        embeddingTestResult = nil
        Task {
            await EmbeddingService.shared.configure(
                apiKey: embeddingApiKey,
                model: model,
                baseURL: embeddingBaseURL.isEmpty ? nil : embeddingBaseURL
            )
            do {
                _ = try await EmbeddingService.shared.embed(text: "这是一段需要向量化的文本")
                await MainActor.run {
                    embeddingTestResult = "Embedding 连接成功"
                    isTestingEmbedding = false
                }
            } catch {
                await MainActor.run {
                    embeddingTestResult = "Embedding 连接失败: \(error.localizedDescription)"
                    isTestingEmbedding = false
                }
            }
        }
    }
}
