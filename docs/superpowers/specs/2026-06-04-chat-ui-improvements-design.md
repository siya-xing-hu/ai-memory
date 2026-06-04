# Chat UI 改进设计

## 背景

当前 HomeView 的聊天界面已基本成型，但在消息展示顺序、交互模式和输入体验上需要优化，使其更接近微信的使用体验。

## 目标

1. 消息严格按时间先后顺序展示
2. 删除批量响应模式，只保留交互问答模式
3. 输入框支持长内容输入（自动扩展 + 全屏编辑）

## 设计决策

### 1. 消息时间排序

**方案：** 在 `DayChatStore.messagesForToday()` 返回前按 `createdAt` 升序排序。

**为什么：** SwiftData 的数组关系在默认情况下按插入顺序存储，但如果存在异步操作或未来支持消息编辑/重排，显式排序更可靠。

### 2. 删除 Batched 模式

**需要删除的内容：**
- `ConversationMode` 枚举及 `SettingsView` 中的模式切换
- `ChatInputBar` 的 `canTriggerAI` 和 `onTriggerAI` 参数及触发按钮
- `HomeView` 中的 `hasPendingUserMessages` 和 `triggerAI` 方法
- `DayChatStore.triggerAIResponse(mode:)` 中的 mode 参数（或简化为无参数）

**保留的行为：**
- 用户发送消息后，AI 立即响应（interactive 模式的行为）

### 3. 输入框长内容支持

**设计：两者结合**

**自动扩展阶段：**
- `TextField` 使用 `axis: .vertical`
- `lineLimit(1...4)`：输入 1-4 行时高度自动扩展
- 超出 4 行时，输入框内部滚动，右侧显示「展开」按钮

**全屏编辑阶段：**
- 点击展开按钮，弹出全屏 `TextEditor` 模态视图
- 支持长文本编辑，完成后点击「完成」返回并填充到输入框
- 模态视图有「取消」和「完成」按钮

**组件变更：**
- `ChatInputBar` 新增 `@State private var showFullScreenEditor: Bool`
- 新增 `FullScreenTextEditor` 组件（内部或独立文件）

## 组件变更清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `DayChatStore.swift` | 修改 | `messagesForToday()` 返回排序后的数组；简化 `triggerAIResponse` 移除 mode 参数 |
| `ChatView.swift` | 修改（可选） | 如 `messagesForToday` 已排序，此处可不变；否则显式排序 |
| `ChatInputBar.swift` | 修改 | 移除 `canTriggerAI`/`onTriggerAI`；添加展开按钮和全屏编辑状态 |
| `HomeView.swift` | 修改 | 移除 `conversationMode` 相关逻辑；移除 `hasPendingUserMessages` 和 `triggerAI` |
| `SettingsView.swift` | 修改 | 移除对话模式切换设置 |
| 新增 `FullScreenTextEditor.swift` | 新增 | 全屏文本编辑器模态视图 |

## 交互流程

### 消息发送流程（删除 batched 后）

```
用户输入内容 → 点击发送
  → HomeView.sendMessage() 调用 store.addUserMessage()
  → 自动触发 Task { await store.triggerAIResponse() }
  → AI 响应后 store.addAIMessage()
  → ChatView 更新，滚动到底部
```

### 长文本输入流程

```
用户输入内容超过 4 行
  → 输入框内部滚动，显示展开按钮
  → 用户点击展开按钮
  → 弹出 FullScreenTextEditor 模态视图
  → 用户编辑长文本
  → 点击「完成」→ 文本填充回输入框
  → 点击「发送」→ 正常发送流程
```

## 数据流

- `HomeView` 持有 `inputText`（`@State`）
- `ChatInputBar` 通过 `@Binding` 绑定 `inputText`
- 全屏编辑器通过回调或绑定将编辑后的文本传回 `ChatInputBar`

## 错误处理

- 全屏编辑器「取消」时不保存修改
- 输入框为空时发送按钮禁用（保持现有行为）

## 回滚计划

如需要恢复 batched 模式，可从 git 历史恢复 `ConversationMode` 及相关代码。
