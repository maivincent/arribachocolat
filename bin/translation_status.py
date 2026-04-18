#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Track and manage translation review status.

Usage:
  python bin/translation_status.py                     # list posts pending review
  python bin/translation_status.py --mark FILE [FILE]  # mark post(s) as reviewed

FILE is a bare filename, e.g. 2026-04-12-anquria-63-macambo.md (no path needed).
--mark removes needs_review from both en and es versions of the named post(s).
"""

import argparse
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
LANGS = ["en", "es"]


# ── YAML helpers ──────────────────────────────────────────────────────────────

def split_front_matter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        return {}, text
    parts = text.split("---\n", 2)
    if len(parts) < 3:
        return {}, text
    return yaml.safe_load(parts[1]) or {}, parts[2]


def rewrite_front_matter(path: Path, fm: dict) -> None:
    """Write updated front matter back to a post, preserving the body."""
    content = path.read_text()
    _, body = split_front_matter(content)
    fm_str = yaml.dump(fm, allow_unicode=True, default_flow_style=False, sort_keys=False)
    path.write_text(f"---\n{fm_str}---\n{body}")


# ── Commands ──────────────────────────────────────────────────────────────────

def cmd_list() -> None:
    pending: dict[str, list[str]] = {lang: [] for lang in LANGS}

    for lang in LANGS:
        posts_dir = ROOT / "_i18n" / lang / "_posts"
        if not posts_dir.exists():
            continue
        for post in sorted(posts_dir.glob("*.md")):
            fm, _ = split_front_matter(post.read_text())
            if fm.get("needs_review"):
                pending[lang].append(post.name)

    total = sum(len(v) for v in pending.values())
    if total == 0:
        print("All translations have been reviewed.")
        return

    print("Pending review:")
    for lang in LANGS:
        for name in pending[lang]:
            print(f"  [{lang}] {name}")

    counts = ", ".join(f"{len(pending[l])} in {l}" for l in LANGS)
    print(f"\n{total} post(s) pending — {counts}")


def cmd_mark(filenames: list[str]) -> None:
    for name in filenames:
        name = Path(name).name  # accept full paths too
        marked = []
        for lang in LANGS:
            post = ROOT / "_i18n" / lang / "_posts" / name
            if not post.exists():
                print(f"  [{lang}] {name} — not found, skipping")
                continue
            fm, _ = split_front_matter(post.read_text())
            if not fm.get("needs_review"):
                print(f"  [{lang}] {name} — already reviewed")
                continue
            fm.pop("needs_review")
            rewrite_front_matter(post, fm)
            marked.append(lang)
        if marked:
            print(f"  Marked as reviewed: {name} ({', '.join(marked)})")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Manage translation review status.")
    parser.add_argument("--mark", nargs="+", metavar="FILE",
                        help="Mark specific post(s) as reviewed (removes needs_review flag)")
    args = parser.parse_args()

    if args.mark:
        cmd_mark(args.mark)
    else:
        cmd_list()


if __name__ == "__main__":
    main()
