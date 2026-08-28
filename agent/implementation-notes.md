# Implementation Notes

## Phase 0

- Retained the existing Flutter toolchain.
- Added no provider or architecture dependency; retained Flutter's scaffolded
  Cupertino icon-font package because Flutter web's framework icon scan expects
  the font even though the current Material shell does not directly use it.
- Kept domain types independent from Flutter.
- Added a deterministic `ExpiryRiskService` contract without implementing the
  Phase 2 classification rules.
- Flutter's Android migrator added explicit compatibility flags for the current
  Gradle behavior during the first verified Android build.

## Verification

- `dart format --output=none --set-exit-if-changed lib test` — PASS (19 files).
- `flutter analyze` — PASS, no issues.
- `flutter test` — PASS, 17 tests.
- `flutter build web --dart-define-from-file=config/env.example.json` — PASS.
- `flutter build apk --debug --dart-define-from-file=config/env.example.json` — PASS.

Flutter reports that the scaffolded Gradle 8.14, Android Gradle Plugin 8.11.1,
and Kotlin 2.2.20 versions will require upgrades in a future Flutter release.
They build successfully today; upgrading the native toolchain is intentionally
deferred to a focused maintenance slice.
