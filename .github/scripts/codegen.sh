#!/usr/bin/env bash
# Generated files are not committed: build them in every package that uses build_runner.
set -euo pipefail
for pubspec in apps/*/pubspec.yaml packages/*/pubspec.yaml packages/modules/*/pubspec.yaml; do
  [ -f "$pubspec" ] || continue
  if grep -qE '^[[:space:]]+build_runner:' "$pubspec"; then
    (cd "$(dirname "$pubspec")" && dart run build_runner build)
  fi
done
