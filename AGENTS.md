# Agent Instructions

Instructions for any AI coding agent (Claude Code, Codex, Copilot, Cursor, etc.) working in this repo.

## Project

xcNav is a Flutter app (Android + iOS) for cross-country paramotor navigation and group flying.

- `lib/models/` – plain data/logic (flight logs, waypoints, fuel reports, GPS filtering, ...)
- `lib/providers/` - Where we were putting "provider" classes but slowly phasing these out in favor of global services
- `lib/services/` - Global state style services.
- `lib/screens/`, `lib/views/`, `lib/widgets/`, `lib/dialogs/` – UI
- `assets/translations/` – localization strings
- `test/` – unit and widget tests (`test/mock_providers.dart` has shared mocks)
- `lib/secrets.dart` is required to build; copy from `lib/secrets.dart.example`. Never commit real secrets.

## Workflow

- Run `flutter analyze` and `flutter test` after making changes; fix anything you introduced.
- Add or update tests in `test/` for logic changes.
- Match the style of surrounding code.
- Commit messages reference the GitHub issue when there is one, e.g. `fixes #295 filter out GPS jumps`.

## Version bump (required)

Every change set an agent makes to the app must bump the app version in `pubspec.yaml`.

The format is `version: MAJOR.MINOR.PATCH+BUILD` (e.g. `2.10.29+250`).

- Increment **PATCH by 1** and **BUILD by 1**: `2.10.29+250` -> `2.10.30+251`.
- Bump only **once per change set**, not once per edit. Before bumping, compare against the last commit
  (`git diff HEAD -- pubspec.yaml`). If the version has already been bumped in the uncommitted work, leave it alone.
- Bump MINOR if we add a large feature, do a heavy rework, update dependencie's major versions, or make a change to any communication protocol.
- Do not bump MAJOR unless the user asks; when they do, reset PATCH to 0 and still increment BUILD.
- BUILD must always increase; it is the Android `versionCode` / iOS `CFBundleVersion`.
- Skip the bump only for changes that don't affect the shipped app (e.g. docs, agent instructions, CI config, scripts in `scripts/`).
