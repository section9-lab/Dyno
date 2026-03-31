# Dyno

A macOS AI assistant app built with SwiftUI + SwiftData, powered by SwiftAgent.

## Overview

Dyno is a macOS native AI assistant that provides:

- Chat interface with markdown rendering
- Voice input via speech recognition
- Screen capture and OCR analysis
- Multi-model support (OpenAI, Ollama, etc.)
- Session persistence and history

## Requirements

- macOS 15.7+
- Xcode 16+

## Installation

1. Clone the repository
2. Open `Dyno.xcodeproj` in Xcode
3. Update SwiftAgent package URL in project settings (replace `YOUR_USERNAME` with your GitHub username)
4. Build and run

## Architecture

```
Dyno/
├── Dyno/                    # Main app target
│   ├── DynoApp.swift        # App entry point
│   ├── ContentView.swift    # Root view
│   ├── AgentManager.swift   # Agent configuration
│   ├── ChatViewModel.swift  # MVVM view model
│   ├── Views/               # SwiftUI views
│   └── ...
├── DynoTests/               # Unit tests
├── DynoUITests/             # UI tests
└── skills/                  # Agent skills (bundled)
```

## Configuration

Dyno uses `ModelRegistry` to manage AI model providers. Configure your API keys in Settings.

## License

MIT
