# Contributing

Vesel is a personal project: one person's health assistant, published so others can read it and run their own copy. Issues are welcome. Pull requests are not accepted yet: they open once the Contributor Licence Agreement check is set up.

## Build

See [README.md](README.md): install `xcodegen` and `uv` with Homebrew, then `cd ios && xcodegen generate` and run on the Simulator. A device install needs your own `Signing.local.xcconfig`.

## Checks

These need Xcode, `xcodegen` and `uv` (see README); nothing else:

```
git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --strict
swift test --package-path ios/Packages/VeselCore
swift test --package-path ios/Packages/VeselStorage
swift test --package-path ios/Packages/VeselSync
swift test --package-path mac/Packages/VeselBackupKit
(cd ios && xcodegen generate && xcodebuild test -project Vesel.xcodeproj -scheme Vesel -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=27.0' -collect-test-diagnostics never -quiet)
(cd mac && xcodegen generate && xcodebuild build -project VeselBackup.xcodeproj -scheme VeselBackup -destination 'platform=macOS' -quiet)
(cd server && uv run pytest)
```

If you don't have that Simulator, use a name and OS from `xcrun simctl list devices`.

The first line checks the Swift code's format with the `swift-format` that comes with Xcode and the settings in `.swift-format`. To fix what it reports, run `git ls-files -z '*.swift' | xargs -0 xcrun swift-format format -i --parallel` before you commit.

`solidvibes lint .` also checks the docs and rules. It needs the Solid Vibes tool: https://solidvibes.stojanovventures.com.

GitHub runs these checks on every pull request and every push to `main` ([.github/workflows/checks.yml](.github/workflows/checks.yml)), with one difference: the app's tests run on an `iPhone 17` Simulator with iOS 27. For the lint it fetches the Solid Vibes tool from its public repo ([solidvibes/solid-vibes](https://github.com/solidvibes/solid-vibes)) at a pinned commit. CI needs no secrets.

## How the repo is worked

[AGENTS.md](AGENTS.md) holds the rules every change follows: what must never happen, the layers, the checks. Topic rules are in `.agents/skills/`. Why things are the way they are: `docs/decisions/`.

Never put real health data in the repo. Test data is made up.

## Licence and CLA

Vesel is open source under the Apache License 2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)). Every pull request will need a signed Contributor Licence Agreement ([CLA.md](CLA.md)) before it can be merged: it gives the UG the rights in your contribution, so Vesel can always be licensed or sold as one piece. For contributions, the CLA applies instead of section 5 of the Apache License.
