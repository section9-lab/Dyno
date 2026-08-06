# PiAgent binaries (not committed to git)

This folder is populated by `scripts/fetch-pi-binary.sh`, which downloads the
official standalone `pi` coding-agent release binaries from
https://github.com/earendil-works/pi/releases for both Apple Silicon
(`arm64/pi`) and Intel (`x64/pi`).

Run this once after cloning, and again whenever the pinned version in the
script changes:

```bash
./scripts/fetch-pi-binary.sh
xcodegen generate
```

The app spawns whichever binary matches the running machine's architecture
via `Process`, in `--mode rpc` (see `PiWork/Core/Agent/PiAgentProcess.swift`).
No Bun, Node, or npm install is required on the end user's machine — the
release binary is fully self-contained.
