# Copilot instructions for Impulse

## Build, test, and lint commands

### Main app build (local development)
```bash
xcodebuild -project Impulse.xcodeproj -scheme Impulse -configuration Debug -destination "platform=macOS" build
```

### Release packaging scripts
```bash
./scripts/build.sh
./scripts/create-release.sh
```

### Tests
There is currently no test target in `Impulse.xcodeproj` (app target only), so there is no runnable repository test suite yet.

When a test target is added, use:
```bash
# full suite
xcodebuild -project Impulse.xcodeproj -scheme Impulse -destination "platform=macOS" test

# single test
xcodebuild -project Impulse.xcodeproj -scheme Impulse -destination "platform=macOS" test -only-testing:<TestTarget>/<TestClass>/<testMethod>
```

### Lint/format
No repo-level SwiftLint/SwiftFormat command is currently configured.

## High-level architecture

- `Impulse/App` is the SwiftUI entry layer. `ImpulseApp` boots SwiftData and shared managers, and `ContentView` composes chat UI + settings sheet.
- `Core/Agent` is the runtime bridge to `SwiftCodingAgent`:
  - `AgentManager` owns provider/model config, SDK creation, connection checks, tool execution tracking, and compaction flow.
  - Tool execution is sandboxed to allowed roots (project directory + user-authorized roots from `SandboxAccessManager`).
  - Agent data lives under the app data root (`skills/`, `memory/`); project session data lives under `projects/<project>/sessions/`.
- `Core/AI` manages providers/models:
  - `ModelRegistry` merges featured providers, cached models.dev catalog data, and live `/models` discovery.
  - Settings UI (`Features/Settings`) edits provider config and writes it through `AgentManager.applyConfig`.
- `Features/Chat` handles conversation UX and persistence:
  - Messages are SwiftData `Item` records, grouped into conversations by `conversationID` in `ChatHistoryService`.
  - Chat data is mirrored to JSONL session snapshots via `AgentSessionStore` for restart continuity.
  - Tool traces and compaction summaries are stored as first-class message kinds and rendered separately in the timeline.
- `Features/Capture/OCR` is background screen OCR:
  - `OCRManager` starts an `OCRCaptureOrchestrator` that captures on idle, deduplicates by visual fingerprint/text, and writes captures under the app data root (`memory/raw/ocr-screenshots/` and `memory/raw/ocr-md/`).

## Key conventions in this codebase

- **Conversation semantics are encoded by `Item.kind` string values**, not enums. Canonical kinds used across UI, history service, and session persistence are:
  - `user_message`
  - `assistant_message`
  - `tool_execution`
  - `compaction_summary`
- **Conversation continuity is dual-layered**:
  1. SwiftData `Item` rows drive current UI state.
  2. Project JSONL snapshots under `~/Library/Application Support/Impulse/projects/<project>/sessions/` restore sessions across app restarts and preserve compaction/tool metadata.
- **Agent storage is decoupled from project storage**:
  - App data root defaults to `~/Library/Application Support/Impulse`.
  - Execution workspace defaults to `~/Library/Application Support/Impulse/workspace` when no project directory is configured.
  - Legacy `~/Library/Application Support/Impulse/.agent` data is migrated into the app data root.
- **Sandbox authorization is explicit and persistent**:
  - Extra writable roots are granted via security-scoped bookmarks (`SandboxAccessManager`) and merged into SDK `allowedRoots`.
  - Project directory access is actively probe-tested from settings.
- **Provider/model configuration pattern**:
  - UI drafts values in `ModelProviderConfigView`, then commits via one `AgentServiceConfig` write (`saveAndConnect` -> `AgentManager.applyConfig`).
  - Provider API keys are stored per provider in `ModelRegistry`; selected config is persisted in `UserDefaults` under `agent.service.config.v3`.
