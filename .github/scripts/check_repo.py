"""Checks that hold before and after there is code: links, task list and label names."""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[2]
errors = []

docs = [*root.glob("*.md"), *root.glob("docs/**/*.md"), *root.glob("specs/**/*.md")]
for doc in docs:
    for target in re.findall(r"\]\(([^)\s]+)\)", doc.read_text(encoding="utf-8")):
        if re.match(r"[a-z]+:|#", target):
            continue
        if doc.parent == root / "docs" / "wiki":
            continue  # wiki links are page names
        if not (doc.parent / target.split("#")[0]).exists():
            errors.append(f"{doc.relative_to(root)}: broken link {target}")

for tasks in root.glob("specs/*/tasks.md"):
    ids = re.findall(r"^- \[[ xX]\] (T\d+)", tasks.read_text(encoding="utf-8"), re.M)
    if len(ids) != len(set(ids)):
        errors.append(f"{tasks.relative_to(root)}: duplicate task ids")

labels = {item["name"] for item in json.loads((root / ".github/labels.json").read_text())}
used = set()
for form in root.glob(".github/ISSUE_TEMPLATE/*.yml"):
    for line in re.findall(r"^labels: (\[.*\])$", form.read_text(), re.M):
        used.update(json.loads(line))
used.update(re.findall(r'^"([^"]+)":$', (root / ".github/labeler.yml").read_text(), re.M))
errors.extend(f"label not defined in labels.json: {name}" for name in sorted(used - labels))

print("\n".join(errors) or "Repository checks passed.")
sys.exit(1 if errors else 0)
