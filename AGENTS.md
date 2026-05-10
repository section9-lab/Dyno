# Repository Guidelines

## Project Overview

Impulse is a native macOS assistant built with SwiftUI and SwiftData. It provides chat, screen-aware OCR, voice input, project-scoped memory, kanban tasks, and configurable model providers such as OpenAI-compatible endpoints, Ollama, or LM Studio. The app is local-first: OCR and speech are on-device, conversations are persisted locally, and file access is mediated through user-granted folders/security-scoped bookmarks.

## Architecture & Data Flow

- Entry point: `Impulse/App/ImpulseApp.swift` creates the SwiftData `ModelContainer`, runs store backup checks, then routes signed-in users to `ContentView` and others to onboarding.
- Main shell: `Impulse/App/Root/ContentView.swift` owns `ChatViewModel`, `AgentManager.shared`, approval/ask centers, and SwiftData `@Query` state for projects, sessions, and kanban tasks.
- Chat flow: `ChatViewModel.sendMessage(...)` inserts a `StoredMessage`, builds a continuation prelude from recent messages and compaction summaries, calls `SessionAgent.sendChat(...)`, then persists assistant output, tool runs, compaction summaries, and todo snapshots.
- Agent runtime: `AgentManager` loads `AgentServiceConfig`, bootstraps runtime directories, wires `ModelRegistry`, and manages `SessionAgentPool` rebuilds when config or allowed roots change.
- Per-session isolation: `SessionAgent`, `SessionAgentPool`, `TodoStore`, and `TaskCoordinator` keep agent state scoped by session; the pool uses LRU caching and avoids rebuilding busy/focused sessions until safe.
- SDK construction: `AgentSDKFactory` resolves working directory and allowed roots from the active project plus `SandboxAccessManager.shared.authorizedRoots`, selects protocol from `AgentServiceConfig.apiKind`, and injects ask/tool/todo dependencies.
- Persistence model: `Impulse/Core/Data/Models/Item.swift` uses path-keyed, denormalized SwiftData entities. `StoredProject`, `StoredSession`, and `StoredKanbanTask` use `projectPath`; session children such as messages/tool runs/compactions/todo snapshots cascade from `StoredSession`.

## Key Directories

- `Impulse/App/` — app entry point, root shell, auth/onboarding integration.
- `Impulse/Core/Agent/` — agent managers, session pool, SDK factory, config stores, persisted run models.
- `Impulse/Core/AI/` — provider catalog and model registry/discovery.
- `Impulse/Core/Data/` — SwiftData entities and store backup/restore support.
- `Impulse/Core/Workspace/` — security-scoped bookmark and authorized-root handling.
- `Impulse/Features/Chat/` — chat views, sidebar, input, message rendering, `ChatViewModel`.
- `Impulse/Features/Capture/` — screen capture permissions/services and Vision OCR orchestration.
- `Impulse/Features/Voice/` — Speech framework recognition.
- `Impulse/Features/Kanban/`, `Impulse/Features/Settings/`, `Impulse/Features/Auth/` — task board, provider/settings UI, auth flows.
- `Impulse/Shared/` — localization, theme/design, extensions, logging/utilities.
- `Impulse/Resources/` — `Info.plist`, entitlements, app icon, assets, localized `.strings` files.
- `ImpulseTests/` — XCTest unit tests wired through `project.yml`.
- `scripts/` — local install, release archive/DMG, notarization, and Xcode-build install helpers.

## Development Commands

```bash
# Regenerate the Xcode project after project.yml changes
xcodegen generate

# Debug build
xcodebuild -project Impulse.xcodeproj \
  -scheme Impulse \
  -configuration Debug \
  -destination "platform=macOS" \
  build

# Run all tests
xcodebuild test -project Impulse.xcodeproj \
  -scheme Impulse \
  -destination "platform=macOS"

# Run one XCTest
xcodebuild -project Impulse.xcodeproj \
  -scheme Impulse \
  -destination "platform=macOS" \
  test -only-testing:ImpulseTests/SessionAgentPoolTests/test_evictLRU_neverEvictsFocused

# Local Release build/sign/install helper
./scripts/build-local.sh

# Release archive/export/DMG, then notarize/upload
./scripts/build.sh
./scripts/create-release.sh [--skip-notarization] [--skip-github]
```

Do not edit `Impulse.xcodeproj` by hand. `project.yml` is the source of truth; regenerate and commit the generated project when project configuration changes.

## Code Conventions & Common Patterns

- Swift 6, SwiftUI, SwiftData, XCTest. No SwiftLint or SwiftFormat is configured; do not introduce formatting/lint tooling without explicit agreement.
- Shared app state is commonly `@MainActor` + `ObservableObject` singletons, e.g. `AgentManager.shared`, `ModelRegistry.shared`, `SandboxAccessManager.shared`, `OCRManager.shared`, `ThemeManager.shared`, `LocalizationManager.shared`.
- SwiftData reads usually happen in views via `@Query`; avoid inventing repository layers unless the surrounding code already uses one.
- Use session-scoped dependency injection through factories/closures in `AgentManager`, `SessionAgentPool`, and `AgentSDKFactory` rather than global mutable state inside sessions.
- Async UI/runtime code uses `Task {}`, `for try await`, `defer` cleanup, and `withCheckedContinuation` for tool approval/ask prompt bridges.
- Persisted/raw contracts matter. Conversation/message kinds are string values such as `user_message`, `assistant_message`, `tool_execution`, and `compaction_summary`; update persistence tests deliberately if these change.
- User/config persistence uses versioned UserDefaults keys and migration fallbacks, e.g. provider config under `agent.service.config.v3`.
- Localization uses `L10n.tr(...)` and resources under `Impulse/Resources/*.lproj`; update localized strings together when changing user-facing text.
- File access: app sandbox entitlement is disabled, but project/file access still flows through user-selected roots and security-scoped bookmarks. Keep entitlements and `Info.plist` usage descriptions in sync when adding system capabilities.
- Design guidance from `.impeccable.md`: native macOS feel, restrained contrast, subtle material depth, clear hierarchy; avoid loud gradients/glossy gimmicks.

## Important Files

- `project.yml` — authoritative XcodeGen configuration, targets, dependencies, signing, schemes.
- `Impulse.xcodeproj/xcshareddata/xcschemes/Impulse.xcscheme` — generated shared scheme; test target is `ImpulseTests`.
- `Impulse/App/ImpulseApp.swift` — `@main`, SwiftData setup, backup check, auth gate.
- `Impulse/App/Root/ContentView.swift` — root app shell and high-level state wiring.
- `Impulse/Core/Agent/Manager/AgentManager.swift` — top-level agent runtime coordinator.
- `Impulse/Core/Agent/Manager/SessionAgent.swift` — per-session agent execution.
- `Impulse/Core/Agent/Manager/SessionAgentPool.swift` — session agent cache/rebuild lifecycle.
- `Impulse/Core/Agent/Manager/AgentSDKFactory.swift` — SDK construction and dependency injection.
- `Impulse/Features/Chat/ViewModels/ChatViewModel.swift` — chat send/persist/restore behavior.
- `Impulse/Core/Data/Models/Item.swift` — SwiftData entities and raw persistence contracts.
- `Impulse/Core/Workspace/SandboxAccessManager.swift` — authorized roots and bookmarks.
- `Impulse/Core/AI/Registry/ModelRegistry.swift` — provider/model discovery and registry state.
- `Impulse/Resources/Info.plist` — bundle metadata, URL scheme, privacy usage strings.
- `Impulse/Resources/Impulse.entitlements` — sandbox/bookmark/file-access entitlements.
- `ImpulseTests/*.swift` — XCTest coverage for config stores, session pool, stored entities, OTP/email validation, backup manager, alert center.

## Runtime/Tooling Preferences

- Required: macOS 14.0+, Xcode 16.0+, Swift 6.0 toolchain, XcodeGen.
- Package manager: Swift Package Manager through Xcode/XcodeGen, not npm/Bun/CocoaPods.
- Required local dependency: `../SwiftHarnessAgent` must exist as a sibling checkout; package resolution/build failures often mean this path is missing.
- Remote dependency: `MarkdownUI` from `https://github.com/gonzalezreal/swift-markdown-ui` starting at `2.4.0`; transitive pins live in `Impulse.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Build outputs are under `.build/`, including `.build/export/Impulse.app`, `.build/dmg/Impulse-*.dmg`, and local DerivedData used by scripts.
- Release/notarization scripts are state-changing and may touch signing identities, `/Applications`, TCC, notarization, and GitHub releases. Do not run them casually; prefer targeted build/test commands for code validation.
- Debug signing is local/manual. Release signing is automatic with team `6BWZP56JX9` in `project.yml`.

## Testing & QA

- Test framework: XCTest hosted macOS unit-test bundle `ImpulseTests`, wired by `project.yml` and the `Impulse` scheme.
- Test naming: one `XCTestCase` class per area, files ending in `Tests.swift`, methods beginning with descriptive `test_...` names.
- Existing coverage includes `AgentConfigStoreTests`, `SessionAgentPoolTests`, `StoredEntitiesTests`, `OTPInputProcessorTests`, `EmailOTPValidationTests`, `StoreBackupManagerTests`, and `UserAlertCenterTests`.
- Prefer deterministic unit tests: isolated `UserDefaults(suiteName:)`, temp directories under `FileManager.default.temporaryDirectory`, in-memory SwiftData containers, injected clocks/schedulers/factories, and no live network calls or sleeps.
- Mark XCTest cases `@MainActor` when exercising MainActor-bound production types, as existing session pool and alert center tests do.
- Add tests next to existing files in `ImpulseTests/`; if adding source/config files requires project changes, update `project.yml`, run `xcodegen generate`, then run the relevant `xcodebuild test` command.
- Note: `ImpulseTests/StoreBackupManagerTests.swift.bak` is an observed backup artifact, not a convention to copy.
