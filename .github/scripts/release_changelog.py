#!/usr/bin/env python3
"""
Release CHANGELOG gate + section extractor for the release-as-code workflow
(.github/workflows/release.yml, ADR-0031; adapted from pdlourenco/disciplined-
project-seed's release_changelog.py, ADR-0015).

Two responsibilities, kept out of inline workflow one-liners so the gate logic
is exercisable without pushing a tag:

  validate  Assert the pushed tag's version has a dated CHANGELOG section AND
            that the [Unreleased] section carries no entries at the tagged
            commit (catches "tagged before cutting the release section"). Exits
            non-zero with an actionable message on any mismatch; the workflow
            then creates no release.

  extract   Print that version's CHANGELOG section body — used verbatim as the
            GitHub release body.

The CHANGELOG path is a parameter, not hard-coded (the workflow passes its
single CHANGELOG_PATH variable). Version headings follow Keep a Changelog:

    ## [Unreleased]
    ## [X.Y] — YYYY-MM-DD        (two- OR three-part version; — en-dash,
    ## [X.Y.Z] — YYYY-MM-DD       em-dash, or plain hyphen accepted)

This fork numbers releases two-part (`2.0`, matching the `version` constant in
adigator.m); the regex also accepts three-part semver so a future scheme change
needs no gate edit.

Run `python3 release_changelog.py --help` for usage.

Copyright 2026 Pedro Lourenço and GMV. Distributed under the GNU General Public
License version 3.0.
"""

from __future__ import annotations

import argparse
import re
import sys

# The CHANGELOG contains non-ASCII (en-dashes, `≤`, accented names). On the
# Linux CI runner stdout is UTF-8, but a maintainer running this locally under a
# legacy Windows console (cp1252) would hit a UnicodeEncodeError on print. Force
# UTF-8 on both streams so `extract`/`validate` are portable.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")  # type: ignore[union-attr]
    except (AttributeError, ValueError):
        pass

# A version heading: "## [2.0] — 2026-07-25" or "## [1.2.3] — 2026-07-25". The
# separator may be an em-dash, en-dash, or hyphen; the date must be ISO
# YYYY-MM-DD. The version is two- or three-part.
VERSION_HEADING = re.compile(
    r"^##\s+\[(?P<ver>\d+\.\d+(?:\.\d+)?)\]\s+[—–-]\s+"
    r"(?P<date>\d{4}-\d{2}-\d{2})\s*$"
)
UNRELEASED_HEADING = re.compile(r"^##\s+\[Unreleased\]\s*$", re.IGNORECASE)
TOP_LEVEL_HEADING = re.compile(r"^##\s")
SUBSECTION_HEADING = re.compile(r"^#{3,}\s")  # ### / #### stubs — not entries
HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
# A markdown link-reference definition: "[2.0]: https://…". These live at the
# bottom of the file and get pulled into the last section's body — strip them
# from the extracted release notes (they render as nothing on GitHub).
LINK_DEF = re.compile(r"^\[[^\]]+\]:\s+\S+")
# The fork's version constant: `version = '2.0';` in adigator.m (single quotes).
SOURCE_VERSION = re.compile(r"^\s*version\s*=\s*'([^']+)'")


def _read(path: str) -> list[str]:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().splitlines()
    except OSError as exc:
        sys.exit(f"error: cannot read CHANGELOG at {path!r}: {exc}")


def _section_body(lines: list[str], start: int) -> list[str]:
    """Lines after heading index `start`, up to the next `## ` heading."""
    body: list[str] = []
    for line in lines[start + 1:]:
        if TOP_LEVEL_HEADING.match(line):
            break
        body.append(line)
    return body


def _find_version(lines: list[str], version: str) -> int | None:
    for i, line in enumerate(lines):
        m = VERSION_HEADING.match(line)
        if m and m.group("ver") == version:
            return i
    return None


def _find_unreleased(lines: list[str]) -> int | None:
    for i, line in enumerate(lines):
        if UNRELEASED_HEADING.match(line):
            return i
    return None


def _unreleased_entries(body: list[str]) -> list[str]:
    """Real changelog entries in an [Unreleased] body, ignoring scaffolding.

    Scaffolding is blank lines, `###`/`####` subsection stubs, and HTML
    comments (including multi-line ones — stripped before the per-line scan so a
    comment spanning lines can't masquerade as an entry).
    """
    text = HTML_COMMENT.sub("", "\n".join(body))
    return [
        ln for ln in text.splitlines()
        if ln.strip() and not SUBSECTION_HEADING.match(ln)
    ]


def _source_version(source_file: str) -> str:
    """The `version = '…'` constant from the tool source (e.g. adigator.m)."""
    for line in _read(source_file):
        m = SOURCE_VERSION.match(line)
        if m:
            return m.group(1)
    sys.exit(
        f"error: no `version = '…'` constant found in {source_file!r} "
        f"(the release gate reads it to cross-check the tag)."
    )


def cmd_validate(path: str, version: str, source_file: str | None = None) -> int:
    lines = _read(path)

    if source_file is not None:
        src = _source_version(source_file)
        if src != version:
            sys.exit(
                f"error: tag version {version!r} does not match the "
                f"`version = '{src}'` constant in {source_file}. Bump the source "
                f"version (or the tag) so they agree before tagging."
            )

    idx = _find_version(lines, version)
    if idx is None:
        sys.exit(
            f"error: no `## [{version}] — YYYY-MM-DD` section found in {path}.\n"
            f"       Add the dated release section for {version} (move the "
            f"[Unreleased] entries into it) before pushing the v{version} tag."
        )

    unreleased = _find_unreleased(lines)
    if unreleased is not None:
        leftovers = _unreleased_entries(_section_body(lines, unreleased))
        if leftovers:
            preview = leftovers[0].strip()
            sys.exit(
                f"error: the [Unreleased] section in {path} still has entries "
                f"at this commit (e.g. {preview!r}).\n"
                f"       Move them into `## [{version}] — <date>` and leave "
                f"[Unreleased] empty before tagging."
            )

    print(f"ok: {path} has a dated [{version}] section and an empty [Unreleased].")
    return 0


def cmd_extract(path: str, version: str) -> int:
    lines = _read(path)
    idx = _find_version(lines, version)
    if idx is None:
        sys.exit(f"error: no `## [{version}] — ...` section found in {path}.")
    body = _section_body(lines, idx)
    # Drop a trailing run of blank lines and link-reference definitions (the
    # `[2.0]: https://…` footer that follows the last section).
    while body and (not body[-1].strip() or LINK_DEF.match(body[-1])):
        body.pop()
    print("\n".join(body).strip("\n"))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("validate", "extract"):
        p = sub.add_parser(name)
        p.add_argument("--changelog", required=True, help="path to the CHANGELOG file")
        p.add_argument("--version", required=True, help="release version, no leading v")
        if name == "validate":
            p.add_argument(
                "--source-file", default=None,
                help="optional: a source file whose `version = '…'` constant "
                     "must match the tag version (e.g. adigator.m)")

    args = parser.parse_args()
    if args.command == "validate":
        return cmd_validate(args.changelog, args.version, args.source_file)
    return cmd_extract(args.changelog, args.version)


if __name__ == "__main__":
    raise SystemExit(main())
