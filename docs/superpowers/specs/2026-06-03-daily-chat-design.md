# AI Memory - 每日聊天式记录设计文档

---

## 1. 概述

将 AI Memory 的交互方式从"逐条独立记录 + 时间线展示"改为**聊天式日记录**。用户打开 App 后看到的就是当天的一整段聊天记录，AI 根据当天状态决定是主动破冰引导还是安静等待。记录按天聚合，自动按话题分组汇总，并生成话题级 embeddings 用于回顾与搜索。

核心原则：
- **用户输入是唯一的记忆来源**，AI 只是辅助和发散思维，绝不篡改用户知识
- **双轨存储**：原始聊天记录（不可变事实层）+ 话题汇总（可重新生成派生层）
- **用户无感知**：汇总、embedding 均在后台静默完成

---

## 2. 数据模型

### 2.1 原始层（Source of Truth）

```swift
@Model
class DayChat: @unchecked Sendable {
    @Attribute(.unique) var date: Date          // 精确到天（startOfDay）
    var messages: [ChatMessage]
    var summarizedAt: Date?                     // nil = 未汇总
    var createdAt: Date
    var updatedAt: Date

    init(date: Date, messages: [ChatMessage] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.date = date
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
class ChatMessage: @unchecked Sendable {
    var id: UUID
    var role: MessageRole          // .user / .ai
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum MessageRole: String, Codable {
    case user
    case ai
}
```

**原则**：
- `DayChat` 只有在用户发送过至少一条消息后才创建，AI 破冰消息不触发创建
- `ChatMessage` 只追加，不修改、不删除
- `ChatMessage` **不存 embedding**

### 2.2 派生层（可重新生成）

```swift
@Model
class TopicSummary: @unchecked Sendable {
    var id: UUID
    var dayChatDate: Date                          // 关联哪一天
    var title: String                              // 话题标题
    var summary: String                            // 基于用户原文的概要
    var citedMessageIds: [UUID]                    // 引用的用户消息 ID
    var aiContextIds: [UUID]                       // 作为上下文的 AI 消息 ID
    var embedding: [Double]?                       // 话题级 embedding
    var createdAt: Date

    init(
        id: UUID = UUID(),
        dayChatDate: Date,
        title: String,
        summary: String,
        citedMessageIds: [UUID],
        aiContextIds: [UUID] = [],
        embedding: [Double]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.dayChatDate = dayChatDate
        self.title = title
        self.summary = summary
        self.citedMessageIds = citedMessageIds
        self.aiContextIds = aiContextIds
        self.embedding = embedding
        self.createdAt = createdAt
    }
}
```

**原则**：
- 重新汇总 = 删除该天所有旧 `TopicSummary`，基于原始消息重新生成
- `summary` 必须直接引用或近似复述用户原文，不可推测、扩写、补全
- AI 消息中的内容如果没有得到用户的进一步回应或补充，不纳入记忆

---

## 3. 首页 UI 与交互流

### 3.1 首页布局

全屏聊天界面，顶部保留导航栏（设置、搜索按钮），底部为输入区。

```
┌─────────────────────────┐
│ AI Memory           ⚙️ 🔍│  ← 导航栏
├─────────────────────────┤
│                         │
│    🤖 早上好！昨天你记   │  ← AI 破冰（当天无记录时）
│    录了xxx，今天要跟     │     不入库，仅 UI 展示
│    进吗？               │
│                         │
│    👤 今天开始写代码了   │  ← 用户消息（右对齐）
│    👤 在做 embedding 对接│
│    👤 遇到 token 报错    │
│                         │
├─────────────────────────┤
│ [🎙️] 记录点什么...  [💬] [↑]│  ← 底部：语音 + 输入框 + AI 按钮 + 发送
└─────────────────────────┘
```

### 3.2 底部输入区

从左到右：
- **🎙️ 语音按钮**（红色圆形）：长按录音或点击进入语音页面
- **输入框**（多行，最多 4 行，灰底圆角）
- **💬 AI 按钮**（仅模式 A 可见）：点击后 AI 把上次回复后的所有用户新消息打包生成一次回复
- **↑ 发送按钮**：有内容时蓝色可用，空时灰色禁用

### 3.3 交互状态

| 状态 | 行为 |
|------|------|
| **当天首开 + 无记录** | AI 显示破冰消息（UI 层，不入库），引导用户开始记录 |
| **当天首开 + 有记录** | 加载已有聊天记录，AI 不发消息，安静等待 |
| **用户发送中** | 消息立即出现在右侧，本地先入库 |
| **AI 回复中** | 左下角显示"思考中..."，**不阻止**用户继续发送 |
| **AI 回复完成** | 显示在左侧，追加到 `DayChat.messages` |

### 3.4 对话模式（可配置）

设置中提供模式切换：

#### 模式 A：批量响应（默认）
- 用户连续输入多条，AI 完全沉默
- 用户点击 **💬 AI 按钮** → AI 打包"上次 AI 回复之后"的所有用户新消息，发给 LLM 生成一次回复
- AI 思考期间用户仍可继续输入和发送，新消息排在 AI 回复后面
- 无未回复消息时，AI 按钮灰色禁用

#### 模式 B：交互问答
- 每条用户消息立即触发一次 AI 回复
- AI 生成期间输入框可输入但发送按钮禁用（或允许排队）

---

## 4. AI 行为设计

### 4.1 核心定位

AI 是**思维发散助手**，不是知识库：
- 不回答"怎么做"类问题（如"如何学 Python"），而是反问"为什么想学"或关联历史记忆
- 每次回复只提 1-2 个相关问题，保持简洁
- 语气像朋友聊天，不要像老师讲课

### 4.2 破冰消息

当天无记录时，AI 在 UI 层显示引导，不写入数据库。

**数据来源优先级**：
1. **昨天** → 昨天最后一条话题的跟进建议
2. **去年今天** → 如果有历史数据，提示"去年的今天你在做 xxx"
3. **上周今天 / 上月今天** → 类似模式
4. **未来日程** → 基于历史记录推断的待办/生日/事件提醒
5. **通用开场** → 如果以上都没有，简单问候 + 建议记录方向

**规则**：
- 只提 1 个方向，不超过 2 句话
- 不要强行关联，无相关数据时用通用开场
- 是引导不是建议，不替用户决定该做什么

### 4.3 批量回复 Prompt（模式 A）

```
System: 你是一个思维发散助手，帮助用户整理和延伸思路。
你绝对不能提供知识性回答。你的任务是：
1. 通过提问帮助用户理清自己的思路
2. 把用户当前的想法和他过去记录中的相关话题联系起来
3. 引导用户深入思考同一话题的层次

规则：
- 不回答"怎么做"类问题，而是反问"为什么想做"或"之前是否接触过"
- 每次回复只提 1-2 个相关问题，保持简洁
- 如果用户只是记录事实（无提问），帮他联系历史记忆或提示遗漏角度
- 语气像朋友聊天，不要像老师讲课
```

### 4.4 破冰 Prompt

```
System: 生成一句简短的引导，帮用户打开话匣子。
可选方向（按优先级，有数据才用）：
1. 昨天的话题 → "昨天你提到了xx，今天有什么进展？"
2. 去年今天 → "去年的今天你在xx，一年后回看有什么变化？"
3. 上周/上月今天 → 类似
4. 历史中的未完成任务 → "之前你计划xx，后来怎么样了？"
5. 通用 → "今天想记录点什么？"

规则：
- 只提 1 个方向，不超过 2 句话
- 不要强行关联，无相关数据时用通用开场
- 是引导不是建议，不替用户决定该做什么
```

---

## 5. 每日汇总（TopicSummary 生成）

### 5.1 触发时机

**方案 B：日期变化兜底**
- 每次 App 打开或前台激活时，扫描所有 `date < 今天 && summarizedAt == nil` 的 `DayChat`
- 逐一异步汇总，用户无感知
- 单天汇总失败不标记 `summarizedAt`，下次启动重试

### 5.2 执行流程

```
1. 取出某一天的 DayChat
2. 提取所有用户消息（role == .user）和 AI 消息（role == .ai）
3. AI 消息作为上下文帮助理解对话连贯性，但不决定汇总内容
4. 调用 LLM：
   - System: "你是一个忠实记录助手。必须基于用户原文整理，不得添加、修改或杜撰内容。"
   - 完整对话作为上下文
   - 输出 JSON: [{title, summary, citedMessageIds, aiContextIds}, ...]
5. 对每个 topic：
   - 生成 embedding（基于 title + summary）
   - 创建 TopicSummary 记录
6. 标记 DayChat.summarizedAt = now()
```

### 5.3 汇总 Prompt

```
System: 你是一个忠实记录助手。你需要阅读一天内的对话记录，
按话题整理用户的记忆。

【内容判定原则】
- 只有用户明确表达、确认或补充的内容才能进入记忆
- AI 的提问如果没有得到用户的进一步展开，不纳入记忆
- 必须直接引用或近似复述用户原文，不得推测、扩写、补全

【关键事实保留规则】
汇总的 summary 字段必须显式包含用户消息中出现的：
- 时间（日期、星期、时段、截止日、纪念日等）
- 地点（城市、场所、具体位置）
- 人物（名字、关系）
- 职业/工作信息（公司、项目、职位）
- 个人偏好（喜好、习惯、价值观）
- 承诺/计划/事件
- 数字/金额/量化信息

宁可冗长也不要丢失这些事实。如果用户原文已包含完整事实，
直接引用原文是最安全的做法。

输出格式：
[{
  "title": "话题标题",
  "summary": "基于用户原文的概要，包含关键事实",
  "citedMessageIds": [用户消息ID列表],
  "aiContextIds": [作为上下文的AI消息ID列表]
}]
```

### 5.4 失败处理

- 单天汇总失败 → 不标记 `summarizedAt`，下次启动重试
- 配额 / 网络问题 → 静默重试，不打扰用户
- 重试间隔：指数退避，最大间隔 1 小时

---

## 6. Embedding 策略

### 6.1 仅话题级 Embedding

- `ChatMessage` **不存 embedding**
- `TopicSummary` 在生成时同时生成 embedding（基于 `title + "\n" + summary`）
- 搜索只基于 `TopicSummary.embedding` 做语义检索

### 6.2 搜索体验

搜索入口在首页右上角。用户输入查询词时：
1. 对查询词生成 embedding
2. 与所有 `TopicSummary.embedding` 做余弦相似度计算
3. 按相似度排序，阈值 0.7
4. 展示结果：日期 → 话题标题 → 摘要摘要，可展开查看该话题的原始消息

---

## 7. 回顾查询

### 7.1 数据源

回顾是 AI 破冰和主动回顾的核心数据源：

| 查询类型 | 检索方式 | 数据来源 |
|----------|----------|----------|
| 昨天 | `Calendar.date(byAdding: .day, value: -1)` | 昨天的 `TopicSummary` |
| 去年今天 | `.month` + `.day` 匹配 | 所有历史 `TopicSummary` |
| 上周今天 | `.weekday` + 最近 1-4 周 | 同星期几的近期 `TopicSummary` |
| 上月今天 | 同日期（如 6 号）近期月份 | 同日期的 `TopicSummary` |
| 未来日程 | 基于 `TopicSummary.summary` 时间实体识别 | 模糊匹配"下周三"、"下个月"等 |

### 7.2 实现

- 本地遍历所有 `TopicSummary`，用 `Calendar.dateComponents` 做匹配
- 数据量小（一年 365 天），本地遍历性能足够
- 检索结果按相关度 / 时间排序，取 Top 3 用于破冰消息生成

---

## 8. 设置与配置

设置中新增选项：

| 配置项 | 类型 | 默认值 |
|--------|------|--------|
| 对话模式 | 枚举（批量 / 交互） | 批量 |
| AI 按钮触发方式 | 枚举（手动 / 静默 N 秒） | 手动 |
| LLM API Key | 字符串 | - |
| Embedding API Key | 字符串 | - |
| 模型选择 | 枚举 | Custom |
| Base URL | 字符串 | - |

---

## 9. 迁移方案

现有 `Memory` 模型（逐条独立记录）需要迁移到新模型：

1. 读取所有旧 `Memory` 记录
2. 按 `createdAt` 的日期分组
3. 每组创建一个 `DayChat`，每条 `Memory` 转换为一个 `ChatMessage(role: .user)`
4. 标记所有 `DayChat.summarizedAt = nil`，让系统在下次启动时自动补汇总
5. 旧 `Memory` 数据保留一段时间后可删除

---

## 10. 接口变更

### 10.1 AIService 新增

```swift
func generateIcebreaker(for date: Date) async throws -> String
func generateResponse(for messages: [ChatMessage], context: [TopicSummary]?) async throws -> String
func summarize(dayChat: DayChat) async throws -> [TopicSummary]
```

### 10.2 MemoryStore 重构

```swift
class DayChatStore: @unchecked Sendable {
    // 获取或创建今天的 DayChat（仅当用户发过消息时才创建）
    func dayChat(for date: Date) -> DayChat?
    
    // 添加用户消息
    func addUserMessage(content: String) async
    
    // 添加 AI 消息
    func addAIMessage(content: String)
    
    // 检查并汇总过期 DayChat
    func summarizePendingDayChats() async
    
    // 搜索
    func search(query: String) async
    
    // 回顾查询
    func topicSummariesForDate(_ date: Date) -> [TopicSummary]
    func topicSummariesForSameDayLastYear() -> [TopicSummary]
    func topicSummariesForSameWeekday() -> [TopicSummary]
}
```

---

## 附录：文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `App/Models/Memory.swift` | 重命名/重构 | 改为 `DayChat.swift`，替换模型 |
| `App/Models/ChatMessage.swift` | 新建 | 聊天记录消息模型 |
| `App/Models/TopicSummary.swift` | 新建 | 话题汇总模型 |
| `App/ViewModels/MemoryStore.swift` | 重命名/重构 | 改为 `DayChatStore.swift` |
| `App/Views/HomeView.swift` | 修改 | 改为全屏聊天界面 |
| `App/Views/TimelineView.swift` | 删除 | 被聊天界面替代 |
| `App/Views/ChatView.swift` | 新建 | 聊天消息列表视图 |
| `App/Views/SearchView.swift` | 修改 | 改为基于 TopicSummary 的搜索 |
| `App/Services/AIService.swift` | 修改 | 新增破冰、回复、汇总方法 |
| `App/Services/EmbeddingService.swift` | 修改 | 仅生成 TopicSummary embedding |
| `App/Views/SettingsView.swift` | 修改 | 新增对话模式选项 |
