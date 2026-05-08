# Contributing to Impulse

Thanks for the interest. This doc covers everything you need to build Impulse from source, run tests, and submit changes.

## Prerequisites

- macOS 14.0 or later
- Xcode 16.0 or later
- Swift 6.0 toolchain (ships with Xcode 16)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- A clone of [`SwiftHarnessAgent`](https://github.com/section9-lab/SwiftHarnessAgent) at the **sibling level** of this repo:

  ```
  parent/
  ├── Impulse/            # this repo
  └── SwiftHarnessAgent/  # local path dependency
  ```

  If the build fails with `package not found`, this is the reason.

## Build from source

```bash
# 1. Clone alongside SwiftHarnessAgent
git clone https://github.com/section9-lab/Impulse.git
git clone https://github.com/section9-lab/SwiftHarnessAgent.git

# 2. Generate the Xcode project (project.yml is the source of truth)
cd Impulse
xcodegen generate

# 3a. Open in Xcode
open Impulse.xcodeproj

# 3b. ...or build from the command line
xcodebuild -project Impulse.xcodeproj \
           -scheme Impulse \
           -configuration Debug \
           -destination "platform=macOS" \
           build
```

> **Never edit `Impulse.xcodeproj` by hand.** It is regenerated from `project.yml`. Edit the YAML, then re-run `xcodegen generate`.

## Local install (signed with your Apple ID)

For day-to-day use without a paid Developer account:

```bash
./scripts/build-local.sh
```

Builds Release, signs with your local `Apple Development` certificate, and offers to drop the app into `/Applications`.

## Release build + DMG

```bash
./scripts/build.sh             # Archive, export, and create .build/dmg/Impulse-<version>.dmg
./scripts/create-release.sh    # Notarize and upload to GitHub Releases
```

The Release config defaults to team `6BWZP56JX9`. Override with the `IMPULSE_DEVELOPMENT_TEAM` env var on CI or other machines.

## Tests

```bash
xcodebuild test -project Impulse.xcodeproj \
                -scheme Impulse \
                -destination "platform=macOS"
```

Test target lives in `ImpulseTests/`. Add new tests next to existing ones; the target is wired through `project.yml`.

## Project layout

See [AGENTS.md](AGENTS.md) for the full annotated tree, key conventions, and per-component function index. Highlights:

- `Impulse/App/` — entry point, root view, onboarding
- `Impulse/Core/` — Agent SDK glue, AI provider registry, persistence, sandbox access
- `Impulse/Features/` — Chat, Voice, Capture (OCR + screen), Kanban, Settings, Auth
- `Impulse/Shared/` — Theme, localization, extensions, utilities

## Conventions

- **No SwiftLint / SwiftFormat** is configured. Don't introduce one in a PR — open an issue first.
- **Conversation kinds are string values**, not enums: `user_message`, `assistant_message`, `tool_execution`, `compaction_summary`. They cross UI, history service, and JSONL persistence.
- **Sandboxing is disabled**; file access goes through `SandboxAccessManager` security-scoped bookmarks.
- **App data root** is `~/Library/Application Support/Impulse/`. Project-scoped state lives under `projects/<project>/`.
- Provider config persists in `UserDefaults` under `agent.service.config.v3`.

## Submitting a change

1. Open or comment on an issue first if the change is non-trivial. Explain what and why.
2. Branch from `main`. Keep PRs focused — one concern per PR.
3. Run the build (`xcodebuild ... build`) and tests (`xcodebuild ... test`) locally.
4. If you touched `project.yml`, run `xcodegen generate` and commit the regenerated `.xcodeproj`.
5. Describe the change, the test you ran, and any UI screenshots if visible behavior changed.

## Permissions and entitlements

Impulse needs Screen Recording, Microphone, and Speech Recognition. Entitlements live in `Impulse/Resources/Impulse.entitlements`. If you add a new system capability, update both the entitlements file and `Info.plist` usage descriptions in the same commit.

## License

By contributing, you agree your contributions are licensed under the [Apache License 2.0](LICENSE).
