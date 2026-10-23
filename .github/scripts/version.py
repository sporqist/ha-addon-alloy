#!/usr/bin/env python3
"""The version rules of this repository, for the PR gate and the revision bot.

A Home Assistant host updates an add-on only when its `version:` changes, and
a published version tag is never pushed again (build-app.yaml skips a tag that
exists). So anything that changes what a host installs - the image, its
AppArmor profile, its options - must come with a new version, or it reaches
nobody. That is what `check` enforces on every pull request.

What counts as such a change, per add-on directory:
  config.yaml   any non-comment line other than `version:`
  Dockerfile    any non-comment line
  apparmor.txt  any non-comment line (`#include` is not a comment)
  rootfs/       any file
Docs, changelog, icons and translations are read from the repository, not the
image, and need no version.

The scheme:
  base add-on   <alloy>[.<rev>]             1.21.0, then 1.21.0.1, 1.21.0.2
  variant       <base>[.<rev>], with <base> padded to four components when a
                revision is added            1.21.0.1, or 1.21.0.0.1 for a
                                             host-only change on base 1.21.0
<alloy> is the Dockerfile's ALLOY_VERSION; a variant's <base> is the tag of the
published base it is built FROM (ARG BASE_IMAGE). Renovate writes the plain
upstream version and so resets the revision; `bump` (the revision bot, run on
Renovate's pull requests) adds one when Renovate changed the image without
moving the version - a base image update.

A variant changed in the same pull request as its base needs no version of its
own: it reaches hosts when the base publishes and Renovate moves the variant
onto it, which is a version change.

Usage:
  version.py check --base <ref> [--head <ref>]
  version.py bump  --base <ref> [--head <ref>] --title <what changed>
Run from the repository root (or pass --repo).
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
REPO = Path.cwd()


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], check=True, capture_output=True, text=True).stdout


def show(ref, path):
    """File content at ref, or None where it does not exist."""
    r = subprocess.run(["git", "-C", str(REPO), "show", f"{ref}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def apps(ref):
    names = git("ls-tree", "--name-only", ref).split()
    return sorted(n for n in names if show(ref, f"{n}/config.yaml") is not None)


def field(text, pattern):
    m = re.search(pattern, text or "", re.MULTILINE)
    return m.group(1) if m else None


def version_of(config):
    return field(config, r'^version: "([^"]+)"$')


def image_of(config):
    return field(config, r"^image: (\S+)$")


def meaningful(text, drop_version=False):
    """The lines that change behaviour: no comments, no blanks."""
    keep = []
    for line in (text or "").splitlines():
        s = line.strip()
        if not s or (s.startswith("#") and not s.startswith("#include")):
            continue
        if drop_version and re.match(r"^version:", line):
            continue
        keep.append(line.rstrip())
    return keep


def inputs(ref, app):
    """Everything about an add-on that a host installs, at ref."""
    rootfs = git("ls-tree", "-r", ref, "--", f"{app}/rootfs") if show(ref, f"{app}/rootfs") is not None else ""
    return {
        "config.yaml": meaningful(show(ref, f"{app}/config.yaml"), drop_version=True),
        "Dockerfile": meaningful(show(ref, f"{app}/Dockerfile")),
        "apparmor.txt": meaningful(show(ref, f"{app}/apparmor.txt")),
        "rootfs": rootfs,
    }


def base_of(ref, app):
    """(base app directory, its tag) for a variant built FROM a published base, else None."""
    pinned = field(show(ref, f"{app}/Dockerfile"), r"^ARG BASE_IMAGE=(\S+?):([0-9.]+)@")
    if not pinned:
        return None
    image = field(show(ref, f"{app}/Dockerfile"), r"^ARG BASE_IMAGE=(\S+?):")
    tag = field(show(ref, f"{app}/Dockerfile"), r"^ARG BASE_IMAGE=\S+?:([0-9.]+)@")
    for other in apps(ref):
        if image_of(show(ref, f"{other}/config.yaml")) == image:
            return other, tag
    sys.exit(f"!! {app}: BASE_IMAGE {image} is no add-on in this repository")


def upstream(ref, app):
    """The version Renovate writes, and the prefix a revision extends."""
    base = base_of(ref, app)
    if base:
        tag = base[1]
        parts = tag.split(".")
        return tag, ".".join(parts + ["0"] * (4 - len(parts)))
    alloy = field(show(ref, f"{app}/Dockerfile"), r'^ARG ALLOY_VERSION="([^"]+)"$')
    if not alloy:
        sys.exit(f"!! {app}: no ALLOY_VERSION in its Dockerfile")
    return alloy, alloy


def revision(ref, app):
    """The revision the version at ref carries over its upstream (0 for none), or None if it fits no scheme."""
    v = version_of(show(ref, f"{app}/config.yaml"))
    plain, prefix = upstream(ref, app)
    if v == plain:
        return 0
    if v and v.startswith(prefix + ".") and v[len(prefix) + 1:].isdigit():
        return int(v[len(prefix) + 1:])
    return None


def next_version(ref, app):
    rev = revision(ref, app)
    if rev is None:
        sys.exit(f"!! {app}: version {version_of(show(ref, f'{app}/config.yaml'))} fits no scheme - see version.py")
    return f"{upstream(ref, app)[1]}.{rev + 1}"


def published(image, tag):
    r = subprocess.run(["bash", str(SCRIPTS / "tag-published.sh"), image, tag])
    return {0: True, 1: False}.get(r.returncode)


def assess(base, head):
    """Per add-on at head: (app, changed, version moved, needs a version, notes)."""
    out = []
    for app in apps(head):
        old, new = show(base, f"{app}/config.yaml"), show(head, f"{app}/config.yaml")
        changed = old is None or inputs(base, app) != inputs(head, app)
        moved = old is None or version_of(old) != version_of(new)
        needs, note = False, ""
        if changed and not moved:
            b = base_of(head, app)
            if b and version_of(show(base, f"{b[0]}/config.yaml")) != version_of(show(head, f"{b[0]}/config.yaml")):
                note = f"changed with its base {b[0]}; it ships when Renovate moves it onto the new base"
            else:
                needs = True
        out.append((app, changed, moved, needs, note))
    return out


def check(base, head):
    errors = []
    for app, changed, moved, needs, note in assess(base, head):
        config = show(head, f"{app}/config.yaml")
        v = version_of(config)
        if needs:
            errors.append(f"{app}: what a host installs changed, but the version is still {v}. "
                          f"Bump it to {next_version(head, app)} and add a '## {next_version(head, app)}' section "
                          f"to {app}/CHANGELOG.md (on a Renovate pull request the revision bot does this).")
            continue
        if note:
            print(f"{app}: {note}")
            continue
        if not moved:
            print(f"{app}: {v}, {'changed' if changed else 'unchanged'}; nothing to release")
            continue
        if revision(head, app) is None:
            plain, prefix = upstream(head, app)
            errors.append(f"{app}: version {v} fits no scheme: expected {plain} or {prefix}.<n>")
            continue
        state = published(image_of(config), v)
        if state is None:
            errors.append(f"{app}: could not ask the registry whether {v} is published - rerun")
        elif state:
            errors.append(f"{app}: {image_of(config)}:{v} is already published, and published tags never change. "
                          f"Use {next_version(head, app)}.")
        else:
            print(f"{app}: {v} is new; it publishes on merge")
    for e in errors:
        print(f"!! {e}")
    return 1 if errors else 0


def bump(base, head, title):
    """Give every add-on that needs a version its next revision, with a changelog section."""
    title = " ".join(title.split()).rstrip(".")
    done = []
    for app, _, _, needs, _ in assess(base, head):
        if not needs:
            continue
        new = next_version(head, app)
        config_path = REPO / app / "config.yaml"
        config = config_path.read_text(encoding="utf-8")
        old = version_of(config)
        config_path.write_text(re.sub(r'(?m)^version: "[^"]+"$', f'version: "{new}"', config, count=1), encoding="utf-8")

        plain, _ = upstream(head, app)
        kept = f"Grafana Alloy {plain} is unchanged." if not base_of(head, app) else f"Still built on the Alloy add-on {plain}."
        changelog_path = REPO / app / "CHANGELOG.md"
        changelog = changelog_path.read_text(encoding="utf-8")
        # Under Renovate's marker, so the next Renovate bump re-emits this
        # section below its own (its template keeps the heading it replaces).
        marker = re.search(r"(?m)^(<!-- renovate:[a-z-]+ -->)\n## " + re.escape(old) + r"\n", changelog)
        if not marker:
            sys.exit(f"!! {app}/CHANGELOG.md: no Renovate marker followed by '## {old}'")
        section = f"{marker.group(1)}\n## {new}\n\n{title}. {kept}\n\n## {old}\n"
        changelog_path.write_text(changelog[:marker.start()] + section + changelog[marker.end():], encoding="utf-8")
        done.append(f"{app} {old} -> {new}")
    print("\n".join(done) if done else "nothing needs a version")
    return 0


def main():
    global REPO
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=["check", "bump"])
    p.add_argument("--base", required=True)
    p.add_argument("--head", default="HEAD")
    p.add_argument("--title", default="")
    p.add_argument("--repo", default=".")
    a = p.parse_args()
    REPO = Path(a.repo).resolve()
    if a.command == "check":
        return check(a.base, a.head)
    if not a.title:
        sys.exit("bump needs --title")
    return bump(a.base, a.head, a.title)


if __name__ == "__main__":
    sys.exit(main())
