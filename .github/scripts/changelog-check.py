#!/usr/bin/env python3
"""Fail if Home Assistant would not show this add-on's own release notes.

Home Assistant builds the notes for an add-on update by slicing CHANGELOG.md
with this regex (core, homeassistant/components/hassio/update.py):

    ^#* <latest_version>\\n            # the section to show starts here
    (?:^(?!#* <installed_version>).*\\n)*   # ... and runs until the one it replaces

and, when that does not match, falls back to returning the WHOLE file. Two
things make it fall back, and both have bitten this repo:

  * a heading that carries anything after the version ("## 1.2.3 - 2026-01-01"):
    the pattern needs the newline straight after the version;
  * no section for the version at all, which is what happens when a dependency
    bump moves config.yaml and nobody writes the changelog.

So this asserts, per add-on: the version in config.yaml has a bare heading of
its own, every other heading is bare too, and a real upgrade from the previous
release slices to that one section instead of the whole file.

Usage: changelog-check.py <app directory>
"""

import re
import sys
from pathlib import Path

app = Path(sys.argv[1] if len(sys.argv) > 1 else "alloy")
config = (app / "config.yaml").read_text(encoding="utf-8")
changelog = (app / "CHANGELOG.md").read_text(encoding="utf-8")

version = re.search(r'(?m)^version: "(.+)"$', config).group(1)
headings = re.findall(r"(?m)^(##+) +(.*)$", changelog)

# Every heading a version section: bare, nothing after the version. "### Added"
# and friends are deeper and carry prose, so only the "## " level is checked.
bad = [t for level, t in headings if level == "##" and re.search(r"\s", t.strip())]
if bad:
    print(f"!! {app}/CHANGELOG.md: headings with more than the version on the line:")
    for t in bad:
        print(f"     ## {t}")
    print("   Home Assistant matches '^#* <version>' and shows the whole file when it fails.")
    sys.exit(1)

versions = [t.strip() for level, t in headings if level == "##"]
if version not in versions:
    print(f"!! {app}/config.yaml is {version} but {app}/CHANGELOG.md has no '## {version}' section.")
    print(f"   Newest section is '## {versions[0]}'. Home Assistant would show the whole file.")
    sys.exit(1)

# And the slice is tight: upgrading from the release below it shows that one
# section, not everything. Single-section file: nothing to slice against.
index = versions.index(version)
if index + 1 < len(versions):
    previous = versions[index + 1]
    pattern = re.compile(
        rf"^#* {re.escape(version)}\n(?:^(?!#* {re.escape(previous)}).*\n)*", re.MULTILINE
    )
    match = pattern.search(changelog)
    if not match:
        print(f"!! {app}: Home Assistant's release-notes regex does not match '## {version}'.")
        sys.exit(1)
    if f"## {previous}" in match.group(0):
        print(f"!! {app}: the slice for {version} runs past '## {previous}' into older sections.")
        sys.exit(1)
    lines = len(match.group(0).splitlines())
    print(f"{app}/CHANGELOG.md: {version} over {previous} -> {lines} lines, {len(versions)} sections total")
else:
    print(f"{app}/CHANGELOG.md: {version} is the only section")
