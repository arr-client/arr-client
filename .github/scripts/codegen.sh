#!/usr/bin/env bash
# Generated files are not committed: build them in every package that uses build_runner.
set -euo pipefail
# A builder reads the generated files of the packages it depends on, so those come first: the shared
# packages (core before the others in name order), then the modules, then the app.
for pubspec in packages/*/pubspec.yaml packages/modules/*/pubspec.yaml apps/*/pubspec.yaml; do
  [ -f "$pubspec" ] || continue
  if grep -qE '^[[:space:]]+build_runner:' "$pubspec"; then
    (cd "$(dirname "$pubspec")" && dart run build_runner build)
  fi
  # Helpers for migration tests, from the exported database schemas.
  if [ -d "$(dirname "$pubspec")/drift_schemas" ]; then
    (cd "$(dirname "$pubspec")" &&
      dart run drift_dev schema generate drift_schemas/ test/storage/generated/)
  fi
done
