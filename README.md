<div align="center">
   <img src="Dyno/AppIcon.icon/dyno.png" alt="Dyno icon" width="120" height="120">
   <h1 align="center">Dyno</h1>

   <p align="center">
      Your personal coding assistant for macOS
   </p>
   
  [![GitHub Star](https://img.shields.io/github/stars/section9-lab/Dyno?style=rounded&color=white&labelColor=000000)](https://github.com/section9-lab/Dyno/stargazers)
  [![GitHub license](https://img.shields.io/github/license/section9-lab/Dyno?style=rounded&color=white&labelColor=000000)](LICENSE)
  [![Release Version](https://img.shields.io/github/v/release/section9-lab/Dyno?style=rounded&color=white&labelColor=000000)](https://github.com/section9-lab/Dyno/releases/latest)
  ![GitHub Repo size](https://img.shields.io/github/repo-size/section9-lab/Dyno?style=rounded&color=white&labelColor=000000&label=dmg%20size)
  
  [![Kofi](https://img.shields.io/badge/Kofi-Jack-orange.svg?style=flat-square&logo=kofi)](https://ko-fi.com/jack)
  [![Patreon](https://img.shields.io/badge/Patreon-Jack-red.svg?style=flat-square&logo=patreon)](https://www.patreon.com/jack)

</div>


## 产品特性

**Dyno** 是一款专为 macOS 打造的原生 AI 编程助手，将强大的大语言模型与智能工具调用融为一体，助您高效完成代码编写、调试和理解任务。

### 核心功能

- 自然对话式编程：通过自然语言与 AI 协作，描述编程需求，Dyno 会自动分析并执行相应操作

- 语音输入：长按或拖动麦克风按钮进行语音输入，解放双手，让编程交流更高效（需按 Option 键启用免提模式）

- 屏幕识别与 OCR：智能识别屏幕内容，支持截图分析和 OCR 文字提取，将任何界面内容转化为可讨论的文本

- Markdown 渲染：美观的 Markdown 格式输出，代码高亮清晰易读，响应内容结构化呈现

- 工具调用可视化：实时透视 AI 的执行过程，包括文件读取、编辑、写入以及终端命令，每一步操作清晰可见

- 多模型支持：支持 OpenAI、Ollama 等多种 AI 服务模型，可根据需求灵活切换

- 会话管理：侧边栏组织多个对话线程，支持新建、重命名和删除聊天，重要对话永不丢失

- 本地化会话持久化：所有对话记录自动保存，支持本地工作空间管理，保障数据隐私与安全

- 上下文压缩：通过 compact 命令智能压缩对话历史，在长流程任务中保持上下文效率

- 沙箱权限控制：精细的目录访问权限控制，保障系统安全，可配置授权目录范围

## 使用场景

- 代码编写与重构
- 调试错误与问题排查
- 学习新框架与库
- 解释现有代码逻辑
- 运行测试与命令
- 跨屏幕信息分析

## 系统要求

- macOS 15.7 或更高版本
- 支持 Swift 16 的 Xcode（用于开发）

## 快速开始

1. 克隆仓库
2. 在 Xcode 中打开 `Dyno.xcodeproj`
3. 配置 AI 模型服务（在设置中配置 API Key 等参数）
4. 构建并运行

## 架构概览

```
Dyno/
├── Dyno/                     # 主应用
│    ├── DynoApp.swift         # 应用入口
│    ├── ContentView.swift     # 主界面
│    ├── AgentManager.swift    # AI 智能体管理
│    ├── ChatViewModel.swift   # 聊天状态管理
│    ├── Views/                # 界面组件
│    │    ├── Chat/
│    │    │    ├── InputBar.swift          # 输入栏（文本/语音）
│    │    │    ├── ChatSidebarView.swift   # 对话侧边栏
│    │    │    ├── ChatMessageViews.swift  # 消息渲染
│    │    │    └── AgentResponseView.swift # AI 响应展示
│    │    └── Settings/
│    │         └── ModelProviderConfigView.swift  # 模型配置
│    ├── VisionOCRService.swift     # OCR 视觉服务
│    ├── ScreenCaptureService.swift # 屏幕捕获
│    ├── SpeechRecognitionManager.swift  # 语音识别
│    ├── SandboxAccessManager.swift  # 沙箱权限管理
│    └── ...
├── skills/                   # 预置技能
│    ├── code-reviewer       # 代码审查
│    ├── frontend-design     # 前端设计
│    ├── internal-comms      # 内部通讯
│    └── ...
```

## 隐私与安全

- 所有对话数据本地存储，支持自定义工作空间目录
- 沙箱机制限制模型访问范围，需授权方可访问特定目录
- 支持自定义 API 端点，可使用本地部署的模型服务

## License

MIT
