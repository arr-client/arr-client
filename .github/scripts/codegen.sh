#!/usr/bin/env bash
# Generated files are not committed: build them in every package that uses build_runner.
# --no-test-helpers leaves out what only tests use, for a job that only builds the app.
set -euo pipefail
test_helpers=true
if [ "${1:-}" = --no-test-helpers ]; then test_helpers=false; fi
# A builder reads the generated files of the packages it depends on, so those come first: the shared
# packages (core before the others in name order), then the modules, then the app.
for pubspec in packages/*/pubspec.yaml packages/modules/*/pubspec.yaml apps/*/pubspec.yaml; do
  [ -f "$pubspec" ] || continue
  # Localizations, in the packages that have strings of their own.
  if [ -f "$(dirname "$pubspec")/l10n.yaml" ]; then
    (cd "$(dirname "$pubspec")" && flutter gen-l10n)
  fi
  if grep -qE '^[[:space:]]+build_runner:' "$pubspec"; then
    (cd "$(dirname "$pubspec")" && dart run build_runner build)
  fi
  # Helpers for migration tests, from the exported database schemas.
  if "$test_helpers" && [ -d "$(dirname "$pubspec")/drift_schemas" ]; then
    (cd "$(dirname "$pubspec")" &&
      dart run drift_dev schema generate drift_schemas/ test/storage/generated/)
  fi
done
