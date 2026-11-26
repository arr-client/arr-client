"""Fail a release unless the app version matches the tag and the build number increases."""
import pathlib
import re
import subprocess
import sys

PUBSPEC = "apps/arr_client/pubspec.yaml"


def parse(text):
    match = re.search(r"^version:\s*([^+\s]+)\+(\d+)\s*$", text, re.M)
    if not match:
        sys.exit(f"{PUBSPEC} needs 'version: X.Y.Z+N'")
    return match.group(1), int(match.group(2))


tag = sys.argv[1]
name, build = parse(pathlib.Path(PUBSPEC).read_text(encoding="utf-8"))
if tag != f"v{name}":
    sys.exit(f"tag {tag} does not match app version {name}")

tags = subprocess.run(["git", "tag", "--list", "v*"], check=True, capture_output=True, text=True)
for old in tags.stdout.split():
    if old == tag:
        continue
    shown = subprocess.run(["git", "show", f"{old}:{PUBSPEC}"], capture_output=True, text=True)
    if shown.returncode == 0 and parse(shown.stdout)[1] >= build:
        sys.exit(f"build number {build} is not higher than the one in {old}")
print(f"Releasing {name}, build {build}.")
