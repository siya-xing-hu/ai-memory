# AI Memory

一个 Local First 的 AI 记忆库。用 10 秒记录生活中的任何想法，并在未来随时找回。

## 核心功能

- **文本记录** — 输入任意内容，AI 自动生成摘要和标签
- **语音记录** — 支持语音输入，自动转文字并整理
- **时间线** — 按时间倒序展示记录，支持今天/昨天/本周/本月
- **搜索** — 支持关键词搜索和语义搜索
- **每日回顾** — 每天 21:00 自动生成当日总结
- **记录提醒** — 每日提醒记录
- **iOS 快捷指令** — 快捷记录和语音记录
- **Share Extension** — 支持网页、文本、图片分享

## 技术栈

- SwiftUI (iOS 18+)
- SwiftData
- Provider 模式 AI 层（支持 OpenAI / Claude / Gemini / DeepSeek / Kimi）
- Embedding 语义搜索

## 项目结构

```
App/
├── MainApp.swift              # 应用入口
├── Models/
│   └── Memory.swift           # SwiftData 数据模型
├── Views/
│   ├── HomeView.swift         # 首页
│   ├── TimelineView.swift     # 时间线
│   ├── SearchView.swift       # 搜索页
│   ├── VoiceRecordView.swift  # 语音录制
│   ├── SettingsView.swift     # 设置
│   └── DailyReviewView.swift  # 每日回顾
├── ViewModels/
│   └── MemoryStore.swift      # 数据管理
├── Services/
│   ├── AIService.swift        # AI 处理服务
│   ├── EmbeddingService.swift # Embedding 服务
│   └── NotificationService.swift # 本地通知
└── Providers/
    └── LLMProvider.swift      # LLM Provider 抽象

Intents/                       # iOS 快捷指令
Share/                         # Share Extension
project.yml                    # XcodeGen 项目配置，项目结构的唯一来源
```

## 快速开始

本项目使用 XcodeGen 管理 Xcode 工程，`project.yml` 是唯一需要维护的工程配置文件。

1. 安装 XcodeGen：`brew install xcodegen`
2. 在仓库根目录生成本地工程：`xcodegen generate`
3. 用 Xcode 打开生成的 `AI Memory.xcodeproj`
4. 选择 `AI Memory` scheme 和 iOS 模拟器
5. 在 `SettingsView` 中配置你的 AI API Key
6. 构建并运行

## 文件规范

- 必须提交：`project.yml`、`App/`、`Intents/`、`Share/`、`README.md`、`.gitignore`
- 本地生成，不提交：`AI Memory.xcodeproj/`、`.DerivedData/`、`DerivedData/`、`build/`、`*.xcresult`、`xcuserdata/`
- 测试和临时调试代码不放入当前项目：`AppTests/`、`Tests/` 已加入 `.gitignore`
- 如需调整 Xcode target、Bundle ID、entitlements 或源码目录，只改 `project.yml`，然后重新运行 `xcodegen generate`

## 数据原则

- 所有数据默认存储在本机
- 默认不上传服务器
- 用户完全掌控自己的数据

## License

MIT
