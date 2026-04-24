# AGENTS.md — Impulse

High-signal guidance for OpenCode agents working in this Swift/SwiftUI macOS app.

## Project Generation (Critical)

- **Xcode project is generated via XcodeGen** — the source of truth is `project.yml`
- **Regenerate after editing `project.yml`:**
  ```bash
  xcodegen generate
  ```
- Do NOT manually edit `.xcodeproj` files — they are ephemeral

## Build Commands

**Debug build (local development):**
```bash
xcodebuild -project Impulse.xcodeproj -scheme Impulse -configuration Debug -destination "platform=macOS" build
```

**Release build + DMG:**
```bash
./scripts/build.sh              # Creates .build/dmg/Impulse-*.dmg
./scripts/create-release.sh     # Notarizes and uploads to GitHub Releases
```

**No tests exist** — there is no test target in the project. Do not attempt to run tests.

## Dependencies

- **SwiftCodingAgent**: Local path dependency at `../SwiftCodingAgent` (must exist at sibling level)
- **MarkdownUI**: External package via Swift Package Manager
- If build fails with "package not found", ensure `../SwiftCodingAgent` exists

## Code Structure

```
Impulse/
├── App/
│   ├── ImpulseApp.swift              → @main entry point; initializes SwiftData, AgentManager, OCRManager
│   └── Root/
│       └── ContentView.swift         → Root view; sidebar + chat area; handles conversation state
│
├── Core/
│   ├── Agent/
│   │   ├── Manager/
│   │   │   └── AgentManager.swift    → Central coordinator; SDK lifecycle, chat execution, persistence
│   │   ├── Models/
│   │   │   ├── AgentServiceConfig.swift      → Provider/model config (URL, key, paths)
│   │   │   ├── AgentToolExecution.swift     → Tool execution metadata for UI
│   │   │   ├── PersistedToolExecution.swift → JSON-encodable tool execution
│   │   │   └── SessionConversationSnapshot.swift → Session restore data
│   │   └── Persistence/
│   │       └── AgentSessionStore.swift → JSONL serialization; session save/load
│   │
│   ├── AI/
│   │   ├── Models/
│   │   │   ├── OllamaModel.swift     → Ollama-specific model structure
│   │   │   └── ProviderCatalog.swift → Provider metadata (name, baseURL, key handling)
│   │   └── Registry/
│   │       └── ModelRegistry.swift   → Provider/model registry; /models discovery
│   │
│   ├── Data/
│   │   └── Models/
│   │       └── Item.swift            → SwiftData model; chat message (kind, content, conversationID)
│   │
│   └── Workspace/
│       └── SandboxAccessManager.swift → Security-scoped bookmarks for file access
│
├── Features/
│   ├── Chat/
│   │   ├── Models/
│   │   │   └── ConversationThread.swift → Grouped conversation structure
│   │   ├── Services/
│   │   │   └── ChatHistoryService.swift → Conversation building, sorting, persistence
│   │   ├── ViewModels/
│   │   │   └── ChatViewModel.swift    → Chat UI state; message sending, session management
│   │   └── Views/
│   │       ├── AgentResponseView.swift → Tool execution progress display
│   │       ├── ChatMessageViews.swift  → Message bubble rendering
│   │       ├── ChatSidebarView.swift   → Conversation list sidebar
│   │       ├── InputBar.swift          → Text input + send controls
│   │       └── UserAccountPopover.swift → User menu popover
│   │
│   ├── Settings/
│   │   ├── Components/
│   │   │   └── SettingsCard.swift     → Settings UI component
│   │   └── Views/
│   │       └── ModelProviderConfigView.swift → Provider/model configuration form
│   │
│   ├── Capture/
│   │   ├── OCR/
│   │   │   ├── OCRManager.swift        → OCR orchestration; publishes captures to UI
│   │   │   ├── OCRCaptureOrchestrator.swift → Idle-based capture scheduling
│   │   │   └── VisionOCRService.swift  → Vision framework OCR implementation
│   │   └── ScreenCapture/
│   │       ├── ScreenCapturePermissionManager.swift → Screen capture authorization
│   │       └── ScreenCaptureService.swift → Screenshot capture API
│   │
│   └── Voice/
│       └── SpeechRecognitionManager.swift → Speech-to-text via Speech framework
│
├── Resources/
│   ├── AppIcon.icon/          → App icon assets
│   ├── Assets.xcassets/       → Color/image assets
│   ├── Impulse.entitlements   → Sandbox disabled; bookmarks enabled
│   └── Info.plist             → App metadata; permission descriptions
│
└── Shared/
    ├── Extensions/
    │   ├── StringExtensions.swift → String helpers (isNotBlank)
    │   └── URLExtensions.swift    → URL helpers for agent directories
    └── Utilities/
        └── IdleWatcher.swift      → System idle detection for OCR capture
```

## Key Functions by Component

### AgentManager.swift
- `static let shared` — Singleton access
- `var agentHomeDirectoryURL: URL` — Returns `~/Library/Application Support/Impulse/.agent/`
- `var projectDirectoryURL: URL?` — User-configured project directory
- `func applyConfig(_:)` — Apply new provider config; reinitializes SDK
- `func chat(prompt:contextPrelude:)` — Main chat execution; handles tool polling
- `func compact(customInstructions:)` — Compress conversation history
- `func loadPersistedConversations()` → `[SessionConversationSnapshot]` — Load from JSONL
- `func persistConversations(_:)` — Save to JSONL
- `func refreshServiceStatus()` — Test connection to model provider
- `func verifyProjectDirectoryAccess()` — Test project directory write access
- `private static func makeSDK(config:)` — Creates `AgentSDK` instance with tool policies

### ChatViewModel.swift
- `func sendMessage(modelContext:agent:conversationItems:persist:)` — Handle user input; dispatch to agent
- `func startNewChat(agent:)` — Reset conversation state
- `func loadConversationsFromSessionFilesIfNeeded(items:modelContext:agent:)` — Restore from JSONL on launch
- `func persistConversationsToSessionFiles(items:agent:)` — Save conversations to JSONL
- `private func buildContinuationPrelude(from:)` — Build context prelude for continuity

### AgentSessionStore.swift
- `func load(agentHomeDirectory:)` → `[SessionConversationSnapshot]` — Parse JSONL files
- `func save(conversations:agentHomeDirectory:projectDirectory:)` — Write JSONL files
- `private func write(conversation:to:projectDirectory:)` — Serialize single conversation
- Handles `type: session`, `type: message`, `type: compaction` entries

### OCRManager.swift
- `func start(agentHomeDirectory:)` — Start background OCR capture
- `func stop()` — Stop OCR capture
- `@Published var lastCapturedText: String?` — UI observes OCR results

## Key Conventions (Easy to Miss)

**Conversation kinds are string values**, not enums:
- `user_message`, `assistant_message`, `tool_execution`, `compaction_summary`
- Used across UI, ChatHistoryService, and session persistence

**Dual persistence layer:**
- SwiftData `Item` records → current UI state
- JSONL snapshots under `~/Library/Application Support/Impulse/.agent/session/` → cross-restart continuity

**Agent storage is NOT in project directory:**
- Agent Home: `~/Library/Application Support/Impulse/.agent/` (sessions, skills, memory, ocr-captures)
- Default workspace: `~/Library/Application Support/Impulse/workspace/`
- Legacy `.agent/` folders in projects are auto-migrated

**Sandboxing disabled** (`com.apple.security.app-sandbox: false`):
- Uses security-scoped bookmarks (`SandboxAccessManager`) for write access
- Extra roots granted via `allowedRoots` in SDK config

**Provider config pattern:**
- UI drafts in `ModelProviderConfigView` → commits via `AgentManager.applyConfig()`
- Persisted in UserDefaults under `agent.service.config.v3`

**Context prelude for continuity:**
- `buildContinuationPrelude` constructs context header when app restarts
- Includes last 8 messages + compaction summary if available
- Prevents model from resetting context on restart

**Tool execution tracking:**
- `latestToolExecutions` publishes tool calls during active response
- Progress task polls SDK history every 450ms during execution
- Tool executions are persisted as `Item(kind: "tool_execution")`

## Environment Requirements

- macOS 14.0+ (deployment target)
- Xcode 16.0+
- Swift 6.0
- No linting/formatting tools configured (do not introduce SwiftLint/SwiftFormat without asking)

## Existing Instruction Files

- `.github/copilot-instructions.md` — detailed architecture notes from human developers
- This file — agent-specific build/dev workflow guidance

## Build Output Locations

- DerivedData: `.build/`
- DMG: `.build/dmg/Impulse-*.dmg`
- Export: `.build/export/Impulse.app`

## Permissions Required

The app requires these entitlements (already configured in `Impulse.entitlements`):
- Screen capture (`NSScreenCaptureUsageDescription`)
- Microphone (`NSMicrophoneUsageDescription`)
- Speech recognition (`NSSpeechRecognitionUsageDescription`)
- File access via bookmarks (`com.apple.security.files.bookmarks.app-scope`)

---

<important>

## Brainstorming + ExecPlans (vibe-plans)

### Brainstorming Ideas Into Designs (Pre‑Implementation)

Brainstorming Ideas Into Designs.
Help turn ideas into fully formed designs and specs through natural collaborative dialogue.
Start by understanding the current project context, then ask questions one at a time to refine the idea.
Once you understand what you're building, present the design and get user approval.
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it.
This applies to EVERY project regardless of perceived simplicity.

### ExecPlans (Design → Implementation)

After the design is explicitly approved by the user, you may:
- Create or update an ExecPlan document that the coding agent can follow.
- Use the milestones, logs, and validation steps described in .agent/template/PLAN.md.
- Implement the plan autonomously without asking for "next steps" at every stage.

</important>
