# Repository Guidelines

## Project Overview

pi-work is a native macOS project board built with SwiftUI and SwiftData. The app is local-first: it stores project folders and Kanban tasks on-device, keeps lightweight account/auth state locally, and provides diagnostics for backup/restore.

## Architecture & Data Flow

- Entry point: `PiWork/App/PiWorkApp.swift` builds the SwiftData container, runs backup checks, and routes signed-in users to `ContentView`.
- Main shell: `PiWork/App/Root/ContentView.swift` manages project selection, Kanban presentation, settings, and project CRUD.
- Persistence model: `PiWork/Core/Data/Models/Item.swift` stores `StoredProject`; `PiWork/Core/Data/Models/StoredKanbanTask.swift` stores Kanban cards.
- Diagnostics: `PiWork/Core/Data/Persistence/StoreBackupManager.swift` maintains and restores rolling local backups.
- Auth: `PiWork/Core/Auth/` contains sign-in/session management and OpenAuth integration.

## Key Directories

- `PiWork/App/` — app entry point and root shell
- `PiWork/Core/Auth/` — auth models, services, session manager
- `PiWork/Core/Data/` — SwiftData models and backup manager
- `PiWork/Core/Notifications/` — user banner notifications
- `PiWork/Features/Auth/` — onboarding and account UI
- `PiWork/Features/Kanban/` — board views and controller
- `PiWork/Features/Settings/` — general + diagnostics settings
- `PiWork/Resources/` — Info.plist, entitlements, assets, localized strings
- `PiWorkTests/` — XCTest coverage

## Development Commands

```bash
xcodegen generate

xcodebuild -project pi-work.xcodeproj   -scheme PiWork   -configuration Debug   -destination "platform=macOS"   build

xcodebuild test -project pi-work.xcodeproj   -scheme PiWork   -destination "platform=macOS"
```

Do not edit `pi-work.xcodeproj` by hand. `project.yml` is the source of truth.
