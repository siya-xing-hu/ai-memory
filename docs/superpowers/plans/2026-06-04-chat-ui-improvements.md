# Chat UI 改进实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将聊天界面改为严格时间排序，删除批量响应模式，为输入框添加长内容支持（自动扩展 + 全屏编辑）。

**Architecture:** 在现有 SwiftUI/SwiftData 架构上做针对性修改：数据层统一排序、业务层删除 batched 分支、UI 层重构输入栏并新增全屏编辑器组件。

**Tech Stack:** SwiftUI, SwiftData, Observation

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `App/ViewModels/DayChatStore.swift` | 修改 | 消息排序 + 简化 triggerAIResponse |
| `App/Views/ChatInputBar.swift` | 修改 | 移除 trigger 按钮，添加展开按钮 + 全屏编辑状态 |
| `App/Views/HomeView.swift` | 修改 | 删除 conversationMode、hasPendingUserMessages、triggerAI 逻辑 |
| `App/Views/SettingsView.swift` | 修改 | 删除对话模式切换设置 |
| `App/Views/FullScreenTextEditor.swift` | 新增 | 全屏文本编辑器模态视图 |

---

### Task 1: 消息时间排序 + 简化 triggerAIResponse

**Files:**
- Modify: `App/ViewModels/DayChatStore.swift:90-92`
- Modify: `App/ViewModels/DayChatStore.swift:96-119`

- [ ] **Step 1: 修改 messagesForToday 按 createdAt 排序**

将：
```swift
    func messagesForToday() -> [ChatMessage] {
        currentDayChat?.messages ?? []
    }
```
改为：
```swift
    func messagesForToday() -> [ChatMessage] {
        currentDayChat?.messages.sorted(by: { $0.createdAt < $1.createdAt }) ?? []
    }
```

- [ ] **Step 2: 简化 triggerAIResponse 签名（移除 mode 参数）**

将：
```swift
    func triggerAIResponse(mode: ConversationMode) async {
```
改为：
```swift
    func triggerAIResponse() async {
```

- [ ] **Step 3: 删除 triggerAIResponse 中对 mode 的使用**

方法内原本没有使用 `mode` 参数，只需确认删除参数后编译无问题。

- [ ] **Step 4: Build 验证**

Run: `xcodebuild -scheme "AI Memory" -sdk iphoneos -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add App/ViewModels/DayChatStore.swift
git commit -m "feat: sort messages by createdAt, simplify triggerAIResponse signature"
```

---

### Task 2: 重构 ChatInputBar（移除 batched 按钮，添加展开按钮）

**Files:**
- Modify: `App/Views/ChatInputBar.swift`
- Create: `App/Views/FullScreenTextEditor.swift`

- [ ] **Step 1: 创建 FullScreenTextEditor 组件**

在 `App/Views/FullScreenTextEditor.swift` 写入：
```swift
import SwiftUI

struct FullScreenTextEditor: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .padding(8)
                .navigationTitle("编辑内容")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    isFocused = true
                }
        }
    }
}
```

- [ ] **Step 2: 修改 ChatInputBar 结构体签名和内部状态**

将 `ChatInputBar` 从：
```swift
struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onVoice: () -> Void
    let onTriggerAI: () -> Void
    let canTriggerAI: Bool
    let isLoading: Bool
```
改为：
```swift
struct ChatInputBar: View {
    @Binding var text: String
    let onSend: () -> Void
    let onVoice: () -> Void
    let isLoading: Bool
    @State private var showFullScreenEditor = false
```

- [ ] **Step 3: 修改 ChatInputBar body**

将 body 替换为：
```swift
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

                Button(action: { showFullScreenEditor = true }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
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
        .sheet(isPresented: $showFullScreenEditor) {
            FullScreenTextEditor(text: $text)
        }
    }
```

- [ ] **Step 4: Build 验证**

Run: `xcodebuild -scheme "AI Memory" -sdk iphoneos -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add App/Views/ChatInputBar.swift App/Views/FullScreenTextEditor.swift
git commit -m "feat: replace batched trigger with full-screen text editor in input bar"
```

---

### Task 3: 清理 HomeView（删除 batched 模式逻辑）

**Files:**
- Modify: `App/Views/HomeView.swift`

- [ ] **Step 1: 删除 conversationMode 相关状态**

删除：
```swift
    @AppStorage("conversation_mode") private var conversationModeRaw = ConversationMode.batched.rawValue
```
和：
```swift
    private var conversationMode: ConversationMode {
        ConversationMode(rawValue: conversationModeRaw) ?? .batched
    }
```

- [ ] **Step 2: 修改 ChatInputBar 调用（移除 trigger 相关参数）**

将：
```swift
                ChatInputBar(
                    text: $inputText,
                    onSend: { sendMessage(store: store) },
                    onVoice: { isRecording = true },
                    onTriggerAI: { triggerAI(store: store) },
                    canTriggerAI: conversationMode == .batched && hasPendingUserMessages(store: store),
                    isLoading: store.isLoading
                )
```
改为：
```swift
                ChatInputBar(
                    text: $inputText,
                    onSend: { sendMessage(store: store) },
                    onVoice: { isRecording = true },
                    isLoading: store.isLoading
                )
```

- [ ] **Step 3: 简化 sendMessage（发送后总是自动触发 AI）**

将：
```swift
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
```
改为：
```swift
    private func sendMessage(store: DayChatStore) {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        store.addUserMessage(content: text)

        Task {
            await store.triggerAIResponse()
        }
    }
```

- [ ] **Step 4: 删除 triggerAI 和 hasPendingUserMessages 方法**

删除以下两个方法：
```swift
    private func hasPendingUserMessages(store: DayChatStore) -> Bool { ... }
    private func triggerAI(store: DayChatStore) { ... }
```

- [ ] **Step 5: Build 验证**

Run: `xcodebuild -scheme "AI Memory" -sdk iphoneos -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add App/Views/HomeView.swift
git commit -m "feat: remove batched mode from HomeView, always trigger AI after send"
```

---

### Task 4: 清理 SettingsView（删除对话模式切换）

**Files:**
- Modify: `App/Views/SettingsView.swift`

- [ ] **Step 1: 读取 SettingsView 确认对话模式相关代码位置**

- [ ] **Step 2: 删除 `@AppStorage("conversation_mode")` 状态**

- [ ] **Step 3: 删除对话模式 Picker 或切换控件**

- [ ] **Step 4: Build 验证**

Run: `xcodebuild -scheme "AI Memory" -sdk iphoneos -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add App/Views/SettingsView.swift
git commit -m "feat: remove conversation mode setting from SettingsView"
```

---

### Task 5: 删除 ConversationMode 枚举

**Files:**
- Modify: `App/ViewModels/DayChatStore.swift`

- [ ] **Step 1: 删除 DayChatStore 文件底部的 ConversationMode 枚举**

删除：
```swift
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

- [ ] **Step 2: Build 验证**

Run: `xcodebuild -scheme "AI Memory" -sdk iphoneos -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add App/ViewModels/DayChatStore.swift
git commit -m "refactor: remove ConversationMode enum"
```

---

## 自审清单

**1. Spec coverage:**
- [x] 消息时间排序 → Task 1 Step 1
- [x] 删除 batched 模式 → Task 1 Step 2, Task 3, Task 4, Task 5
- [x] 输入框长内容支持 → Task 2 Step 1-3

**2. Placeholder scan:**
- [x] 无 "TBD"/"TODO"
- [x] 无 "add appropriate error handling"
- [x] 无 "similar to Task N"
- [x] 所有代码步骤包含完整代码

**3. Type consistency:**
- [x] `triggerAIResponse()` 无参数，HomeView 调用方式一致
- [x] `ChatInputBar` 签名修改后，HomeView 调用参数一致
- [x] `FullScreenTextEditor` 使用 `@Binding var text: String` 与 `ChatInputBar` 的 `$text` 一致
