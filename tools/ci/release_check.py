#!/usr/bin/env python3
"""Release checks for the tag-driven release flow (`.github/workflows/release.yml`).

  check vX.Y.Z [--base REF] [--notes FILE]
      The tag names the version both sources declare (`build_support/version.zig`
      and `build.zig.zon`); CHANGELOG.md has a dated, non-empty
      `## [X.Y.Z] - YYYY-MM-DD` section opening with a summary and a
      `### Highlights` list; README.md and PLAN.md agree on the declared
      `bench 6` fingerprint; HEAD is on the release line (see `line`).
      With --notes, the release page's text is written there: the unwrapped
      summary, the unwrapped highlights, and a link to the full CHANGELOG at
      the tag.
  line vX.Y.Z [--base REF]
      HEAD is an ancestor of REF (default `origin/master`), or the tag is a
      patch (Z > 0) whose commit descends from the `vX.Y.0` tag on REF: a
      patch cut on a branch from the release while REF holds later work.
  fingerprint
      Prints the declared `bench 6` node count after checking that README.md
      and PLAN.md agree on it.
  version
      Prints the declared package version after checking that
      `build_support/version.zig` and `build.zig.zon` agree.

Exit status 0 on success; 1 with the reason on stderr otherwise.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TAG = re.compile(r"v(\d+\.\d+\.\d+)")
VERSION_ZIG = re.compile(r'pub const current = "(\d+\.\d+\.\d+(?:-dev)?)";')
ZON_VERSION = re.compile(r'\.version = "(\d+\.\d+\.\d+(?:-dev)?)",')
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
README_BENCH = re.compile(r"Manta \d+\.\d+\.\d+ searches `(\d{1,3}(?:,\d{3})*)` nodes")
PLAN_BENCH = re.compile(r"One-thread depth-6 bench is `(\d{1,3}(?:,\d{3})*)` nodes")
CHANGELOG_URL = "https://github.com/maelic13/manta/blob/{tag}/CHANGELOG.md"
HIGHLIGHTS = "### Highlights"
LIST_ITEM = re.compile(r"\s*(?:[-*+]|\d+\.)\s")


class CheckError(Exception):
    pass


def version_of_tag(tag: str) -> str:
    match = TAG.fullmatch(tag)
    if not match:
        raise CheckError(f"tag `{tag}` must read vX.Y.Z with three numbers")
    return match.group(1)


def engine_version(root: Path) -> str:
    """Declared version, checked across build_support/version.zig and build.zig.zon."""
    version_zig = (root / "build_support" / "version.zig").read_text(encoding="utf-8")
    zig_match = VERSION_ZIG.search(version_zig)
    if not zig_match:
        raise CheckError('build_support/version.zig declares no `pub const current = "X.Y.Z";`')
    zon = (root / "build.zig.zon").read_text(encoding="utf-8")
    zon_match = ZON_VERSION.search(zon)
    if not zon_match:
        raise CheckError('build.zig.zon declares no `.version = "X.Y.Z",`')
    if zon_match.group(1) != zig_match.group(1):
        raise CheckError(
            f"build.zig.zon declares {zon_match.group(1)}, "
            f"build_support/version.zig declares {zig_match.group(1)}"
        )
    return zig_match.group(1)


def declared_fingerprint(root: Path) -> int:
    """Declared bench-6 node count, checked across README.md and PLAN.md."""
    readme = (root / "README.md").read_text(encoding="utf-8")
    readme_matches = README_BENCH.findall(readme)
    if len(readme_matches) != 1:
        raise CheckError(
            f"README.md must declare one `Manta X.Y.Z searches \\`N\\` nodes` fingerprint "
            f"(found {len(readme_matches)})"
        )
    plan = (root / "PLAN.md").read_text(encoding="utf-8")
    plan_matches = PLAN_BENCH.findall(plan)
    if len(plan_matches) != 1:
        raise CheckError(
            f"PLAN.md must declare one `One-thread depth-6 bench is \\`N\\` nodes` fingerprint "
            f"(found {len(plan_matches)})"
        )
    readme_nodes = int(readme_matches[0].replace(",", ""))
    plan_nodes = int(plan_matches[0].replace(",", ""))
    if readme_nodes != plan_nodes:
        raise CheckError(
            f"README.md declares bench-6 {readme_nodes}, but PLAN.md declares {plan_nodes}"
        )
    return readme_nodes


def changelog_section(changelog: str, version: str) -> str:
    lines = changelog.splitlines()
    heading = f"## [{version}] - "
    start = next(
        (
            n
            for n, line in enumerate(lines)
            if line.startswith(heading) and DATE.fullmatch(line[len(heading) :].strip())
        ),
        None,
    )
    if start is None:
        raise CheckError(
            f"CHANGELOG.md has no `## [{version}] - YYYY-MM-DD` section; "
            "date [Unreleased] as the release first"
        )
    end = next((n for n in range(start + 1, len(lines)) if lines[n].startswith("## ")), len(lines))
    body = lines[start + 1 : end]
    while body and body[-1].strip() in ("", "---"):
        body.pop()
    text = "\n".join(body).strip()
    if not text:
        raise CheckError(f"the CHANGELOG section for {version} is empty")
    return text + "\n"


def unwrap(text: str) -> str:
    """Join wrapped paragraph and list-item lines: GitHub renders single newlines
    in release notes as hard line breaks. Fenced blocks are left as written."""
    if "```" in text:
        return text
    out: list[str] = []
    for line in text.splitlines():
        joins = (
            out
            and out[-1].strip()
            and line.strip()
            and not line.startswith("#")
            and not LIST_ITEM.match(line)
            and not out[-1].startswith("#")
        )
        if joins:
            out[-1] = out[-1].rstrip() + " " + line.strip()
        else:
            out.append(line.rstrip())
    return "\n".join(out)


def release_notes(section: str, tag: str) -> str:
    """The release page's text: unwrapped summary, unwrapped highlights, and a
    link to the full CHANGELOG at the tag."""
    lines = section.splitlines()
    first = next((n for n, line in enumerate(lines) if line.startswith("### ")), len(lines))
    summary = "\n".join(lines[:first]).strip()
    if not summary:
        raise CheckError("the CHANGELOG section has no summary before its first `###` heading")
    start = next((n for n, line in enumerate(lines) if line.strip() == HIGHLIGHTS), None)
    if start is None:
        raise CheckError(
            f"the CHANGELOG section has no `{HIGHLIGHTS}` list; "
            "the release page shows the summary and the highlights"
        )
    end = next((n for n in range(start + 1, len(lines)) if lines[n].startswith("### ")), len(lines))
    highlights = "\n".join(lines[start + 1 : end]).strip()
    if not highlights:
        raise CheckError(f"the CHANGELOG section's `{HIGHLIGHTS}` list is empty")
    url = CHANGELOG_URL.format(tag=tag)
    return (
        f"{unwrap(summary)}\n\n{HIGHLIGHTS}\n\n{unwrap(highlights)}\n\n"
        f"Every change is in [CHANGELOG.md]({url}), "
        "which every download also includes.\n"
    )


def is_ancestor(root: Path, ancestor: str, descendant: str) -> bool:
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if result.returncode in (0, 1):
        return result.returncode == 0
    raise CheckError(f"cannot compare {ancestor} with {descendant}: {result.stderr.strip()}")


def tag_exists(root: Path, tag: str) -> bool:
    result = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"refs/tags/{tag}^{{commit}}"],
        cwd=root,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def ensure_on_line(root: Path, version: str, base: str) -> str:
    """HEAD is on `base`, or, for a patch X.Y.Z with Z > 0, HEAD descends from
    the `vX.Y.0` tag and that tag is on `base`."""
    if is_ancestor(root, "HEAD", base):
        return f"HEAD on {base}"
    major, minor, patch = version.split(".")
    if patch == "0":
        raise CheckError(f"HEAD is not on {base}")
    line = f"v{major}.{minor}.0"
    if not tag_exists(root, line):
        raise CheckError(f"HEAD is not on {base}, and the patch line's {line} tag does not exist")
    if not is_ancestor(root, line, base):
        raise CheckError(f"HEAD is not on {base}, and {line} is not on {base} either")
    if not is_ancestor(root, line, "HEAD"):
        raise CheckError(f"HEAD is not on {base} and does not descend from {line}")
    return f"HEAD on the {major}.{minor} patch line from {line} on {base}"


def check(root: Path, tag: str, base: str, notes: Path | None) -> str:
    version = version_of_tag(tag)
    declared = engine_version(root)
    if declared != version:
        raise CheckError(f"tag {tag} names {version}, but the sources declare {declared}")
    body = changelog_section((root / "CHANGELOG.md").read_text(encoding="utf-8"), version)
    page = release_notes(body, tag)
    nodes = declared_fingerprint(root)
    where = ensure_on_line(root, version, base)
    if notes is not None:
        notes.write_text(page, encoding="utf-8")
    return (
        f"release check {tag}: both version sources read {version}, CHANGELOG section "
        f"dated with highlights, bench 6 declared {nodes}, {where}"
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("check")
    run.add_argument("tag")
    run.add_argument("--base", default="origin/master")
    run.add_argument("--notes", type=Path)
    line = sub.add_parser("line")
    line.add_argument("tag")
    line.add_argument("--base", default="origin/master")
    sub.add_parser("fingerprint")
    sub.add_parser("version")
    args = parser.parse_args(argv)
    try:
        if args.command == "check":
            print(check(ROOT, args.tag, args.base, args.notes))
        elif args.command == "line":
            print(f"release line {args.tag}: " + ensure_on_line(ROOT, version_of_tag(args.tag), args.base))
        elif args.command == "fingerprint":
            print(declared_fingerprint(ROOT))
        else:
            print(engine_version(ROOT))
    except CheckError as error:
        print(f"release_check: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
