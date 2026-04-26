# Repository Guidelines

## Project Structure & Module Organization
App code lives in `MyShikiPlayer`, split by feature: `Shikimori` holds API/auth clients, `Player` covers playback UI, `Details`, `Progress`, and `AnimeListView.swift` render data, while `Sources` stores shared helpers. SwiftUI assets stay in `MyShikiPlayer/Assets.xcassets`. Unit fixtures sit in `MyShikiPlayerTests/Fixtures`, and UI tests live exclusively in `MyShikiPlayerUITests`. Release artifacts and DerivedData are kept under `build/`, and runtime secrets/configs in `Configuration/*.xcconfig`.

## Build, Test, and Development Commands
- `xed MyShikiPlayer.xcodeproj` to open the workspace in Xcode for day-to-day development.
- `xcodebuild -project MyShikiPlayer.xcodeproj -scheme MyShikiPlayer -destination 'platform=macOS' build` creates a debuggable app; override `CONFIGURATION` as needed.
- `xcodebuild test -project MyShikiPlayer.xcodeproj -scheme MyShikiPlayer -destination 'platform=macOS'` executes the XCTest bundle headlessly.
- `./scripts/lint.sh [--fix]` runs SwiftLint with the repo-provided rules.
- `./scripts/build-dmg.sh` bumps `CURRENT_PROJECT_VERSION`, performs a Release build, and creates a signed DMG in `build/`.

## Coding Style & Naming Conventions
Follow Swift 5 + SwiftUI idioms with two-space indentation. Keep type names ≥3 characters and identifiers ≤50 characters per `.swiftlint.yml`. Respect the opt-in rules (e.g., `closure_spacing`, `explicit_init`) and keep lines under 140 characters. Prefer camelCase for properties/functions, UpperCamelCase for types, and suffix test doubles with `Mock`. Run the linter before pushing to avoid CI failures.

## Testing Guidelines
Tests use XCTest; every new feature needs unit coverage in `MyShikiPlayerTests` and UI smoke in `MyShikiPlayerUITests` when user flows change. Name files as `<Component>Tests.swift` and mirror the production folder layout to ease navigation. Place sample JSON or media inside `MyShikiPlayerTests/Fixtures`. Run `xcodebuild test …` locally and attach `DerivedData/Logs/Test/*.xcresult` to investigate failures. Aim for meaningful assertions over raw snapshotting.

## Commit & Pull Request Guidelines
Adopt the existing history style: short, imperative subjects (`Implement Shikimori auth`) with optional body paragraphs describing rationale or follow-ups. Each PR should link the relevant issue, describe user-facing outcomes, list manual verification (`build`, `lint`, `test`), and include before/after screenshots when UI changes. Keep branch names descriptive (e.g., `feature/shikimori-sync`) and ensure the branch is rebased before requesting review.

## Security & Configuration Tips
Never commit real Shikimori credentials. Copy `Configuration/Secrets.example.xcconfig` to `Secrets.xcconfig`, keep it ignored, and define OAuth keys plus callback URLs there. When touching versioning, update `Configuration/Version.xcconfig` once and let `scripts/build-dmg.sh` handle incremental bumps. Audit new dependencies for App Store compliance before inclusion.
