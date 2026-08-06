# Contributing to pi-work

Thanks for the interest. This document covers the basics for building and testing pi-work locally.

## Requirements

- macOS 14.0+
- Xcode 15.0+
- XcodeGen

## Build

```bash
xcodegen generate
open pi-work.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project pi-work.xcodeproj            -scheme PiWork            -configuration Debug            -destination "platform=macOS"            build
```

## Test

```bash
xcodebuild test -project pi-work.xcodeproj                 -scheme PiWork                 -destination "platform=macOS"
```

## Project layout

- `PiWork/App/` — app entry point and root UI
- `PiWork/Core/` — auth, persistence, notifications
- `PiWork/Features/` — Kanban, settings, auth views
- `PiWork/Resources/` — plist, entitlements, localized strings, icons
- `PiWorkTests/` — XCTest coverage

Do not edit `pi-work.xcodeproj` by hand. Update `project.yml` and regenerate it instead.
