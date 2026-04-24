# Project-First Sidebar And Sessions

## Context

Impulse currently treats chat history as a flat list of conversations keyed only by `conversationID`. The sidebar renders a single-level conversation list, while the selected project directory lives separately in settings as a global execution context. This does not match the intended Codex desktop-style workflow where users first pick a local project, then create and manage multiple sessions under that project.

Relevant files and systems:

- `Impulse/App/Root/ContentView.swift` drives the main layout and sidebar wiring.
- `Impulse/Features/Chat/Views/ChatSidebarView.swift` renders the current single-level sidebar.
- `Impulse/Features/Chat/ViewModels/ChatViewModel.swift` owns selected conversation state and message sending flow.
- `Impulse/Features/Chat/Services/ChatHistoryService.swift` groups `Item` records into `ConversationThread`.
- `Impulse/Core/Data/Models/Item.swift` is the SwiftData message model and currently stores only `conversationID`.
- `Impulse/Core/Agent/Manager/AgentManager.swift` owns the active execution workspace and session persistence entry points.
- `Impulse/Core/Agent/Persistence/AgentSessionStore.swift` persists sessions as flat JSONL files under the storage root.
- `Impulse/Core/Workspace/SandboxAccessManager.swift` already contains directory picker and bookmark authorization logic, which can be reused when users add projects.

Relevant user-approved design decisions:

- Sidebar becomes project-first, similar to Codex desktop.
- Project identity is the absolute local directory path.
- `Add Project` is an explicit sidebar action that opens a directory picker.
- Sessions belong to exactly one project.
- Projects are expanded by default.
- Switching projects does not auto-open a session; the user must click one.
- `New Chat` is disabled until a project is selected.
- Removing a project does not delete files on disk, but it removes the project and all its sessions from Impulse. Re-adding the same path starts fresh.
- Session titles continue to derive from the first user message.

## Goals and Non-Goals

Goals:

- Replace the flat conversation sidebar with a project tree that contains sessions under each project.
- Store session ownership by project path in the data model and persistence layer.
- Allow adding projects from a local directory picker and removing them from Impulse without touching disk contents.
- Make the selected project drive the active agent workspace.
- Ensure sessions are only created inside a selected project.
- Keep the app buildable throughout and end with a passing macOS build.

Non-goals:

- Preserve compatibility with the old flat session storage layout.
- Migrate or recover old session data after project removal.
- Build a separate project management settings screen.
- Introduce tests; the project has no test target.

## Plan / Milestones

1. Refactor core data and persistence to project/session hierarchy.
   - Add project ownership to message/session models.
   - Replace flat session snapshot persistence with project-scoped persistence under the Impulse storage root.
   - Remove assumptions that there is a single global session list.
   - Validation: app compiles after model/service changes; persistence APIs accept project-scoped data.

2. Refactor chat history service and view model state to project-first selection.
   - Introduce project and session view models/types for the sidebar.
   - Track selected project separately from selected session.
   - Require a selected project to create a new session or send a message.
   - Validation: compile and verify the main view can derive project/session structures from `Item` records.

3. Replace the sidebar UI with a project tree and add-project flow.
   - Render projects with nested sessions and default-expanded state.
   - Add explicit `Add Project` and project removal affordances.
   - Disable `New Chat` when no project is selected.
   - Validation: compile and manually inspect the sidebar behavior in the running app if needed.

4. Wire project selection to the agent runtime context and finish cleanup.
   - When a project is selected, update the active workspace used by agent execution.
   - Remove obsolete global project-directory assumptions from the chat flow where they conflict with selected project behavior.
   - Validate by building the macOS app end-to-end with `xcodebuild`.

## Implementation Notes

- Use the absolute project path as the durable project key. This keeps the model simple and matches the approved UX.
- The SwiftData `Item` model will need a new `projectPath` field. Because this is a development-only app iteration, a schema reset is acceptable if needed.
- Persistence should move away from “root/session/*.jsonl” semantics toward “root/projects/<sanitized-project>/sessions/*.jsonl” or an equivalent layout. The exact internal layout can be chosen pragmatically as long as project removal can delete all session state for that project.
- `SandboxAccessManager` should be reused for project selection so a chosen project is immediately authorized for agent access.
- The settings screens currently still mention a global “Project Directory” execution context. They may need wording cleanup or simplification once project selection becomes the primary workflow.

Risks and mitigations:

- Large state refactor may break selection logic.
  - Mitigation: keep changes staged and compile after each milestone.
- Persistence format rewrite may leave stale files in the storage root.
  - Mitigation: in development mode, prefer deleting obsolete project/session artifacts rather than preserving compatibility.
- Sidebar complexity may introduce fragile selection edge cases.
  - Mitigation: make the selection model explicit: selected project path, selected session ID, and clear nil behavior.

## Validation

End-to-end validation for completion:

- `xcodebuild -project Impulse.xcodeproj -scheme Impulse -configuration Debug -destination "platform=macOS" build` succeeds.
- The sidebar shows projects first and sessions nested beneath them.
- `Add Project` opens a folder picker and adds the selected directory as a project.
- Selecting a project does not auto-open a session.
- `New Chat` is disabled without a selected project and creates a session only under the selected project.
- Removing a project removes it and its sessions from the app without deleting the underlying directory.
- OCR output remains under `memory/raw`.

## Log / Journal

- 2026-04-24 18:12 CST: Authored the ExecPlan after user-approved design review. The implementation will replace flat conversations with a project-first sidebar and project-scoped session persistence.
