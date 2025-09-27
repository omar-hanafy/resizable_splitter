# Repository Guidelines

## Project Structure & Module Organization
Main package under `lib/` with public entrypoint `lib/resizable_splitter.dart` re-exporting internals from `lib/src/`. Unit and widget tests live in `test/`, grouped by interaction category (drag, keyboard, semantics, controller). Example showcase app sits in `example/`, with assets in `screenshots/` for docs and marketing.

## Build, Test, and Development Commands
Run `flutter pub get` after dependency changes to refresh the lockfile. Use `flutter analyze` to enforce lint rules from `very_good_analysis`. Execute `flutter test` for the full suite; add `--coverage` when verifying reporting before releases. From `example/`, `flutter run` launches the demo for manual QA on desktop, mobile, or web.

## Coding Style & Naming Conventions
Follow Flutter defaults: two-space indentation, trailing commas on multiline literals, and camelCase for variables, PascalCase for classes. Public APIs should live in `lib/` and be exported through `resizable_splitter.dart`; use package imports (`package:resizable_splitter/...`) because the linter blocks relative paths. Prefer descriptive enum and callback names that reflect user-facing semantics. Format new code with `dart format .` before committing.

## Testing Guidelines
Write tests in `test/` using the Flutter testing framework; mirror filenames with the feature under test (e.g., `splitter_controller_test.dart`). Cover pointer gestures, keyboard navigation, semantics, and layout constraints whenever you touch the associated code paths, aiming to keep controller logic fully covered. When reproducing bugs, start with a failing test and assert on ratios, sizes, and semantics labels to guard regressions.

## Commit & Pull Request Guidelines
Keep commits scoped and message them in the imperative mood (`fix drag threshold`, `add keyboard docs`), matching the current history. Squash fixups locally so PRs read cleanly. Every PR should describe the motivation, list functional changes, and mention how you validated them (tests run, platforms exercised). Attach screenshots or GIFs for UI variants, and link related issues or TODOs.

## Release & Publishing Notes
Update `CHANGELOG.md` in lockstep with pubspec version bumps. Verify the example app on web and desktop before tagging a release. Publishing to pub.dev requires `dart pub publish --dry-run` to confirm metadata and asset inclusion.
