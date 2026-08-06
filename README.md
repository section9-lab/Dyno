<div align="center">
<img src="PiWork/Resources/AppIcon.icon/pi-work.png" alt="pi-work" width="120" height="120">

<h1>pi-work</h1>

<p><b>A native macOS project board for focused local work.</b></p>

[![License](https://img.shields.io/github/license/section9-lab/pi-work?style=flat-square&color=000)](LICENSE)
[![Release](https://img.shields.io/github/v/release/section9-lab/pi-work?style=flat-square&color=000)](https://github.com/section9-lab/pi-work/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14.0%2B-000?style=flat-square)](https://www.apple.com/macos/)
</div>

## What it is

pi-work is a native SwiftUI + SwiftData macOS app for organizing project folders and Kanban tasks locally. It keeps project metadata on-device and offers lightweight account sign-in.

## Features

- Project-scoped Kanban board
- Local SwiftData persistence
- Theme and language settings
- Google or email sign-in for account access

## Build from source

```bash
xcodegen generate
xcodebuild -project pi-work.xcodeproj   -scheme PiWork   -configuration Debug   -destination "platform=macOS"   build
```

Run tests with:

```bash
xcodebuild test -project pi-work.xcodeproj   -scheme PiWork   -destination "platform=macOS"
```

## System requirements

- macOS 14.0 or later
- Xcode 15.0 or later for local development

## License

[Apache License 2.0](LICENSE)
