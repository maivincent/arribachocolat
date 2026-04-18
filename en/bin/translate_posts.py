#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Translate French Jekyll posts to English and Spanish using DeepL.

Usage:
  python bin/translate_posts.py                        # translate new posts only
  python bin/translate_posts.py FILE [FILE ...]        # retranslate specific files
  python bin/translate_posts.py --dry-run              # preview without calling DeepL
  python bin/translate_posts.py --langs en FILE        # one language, specific file

FILE is a filename only, e.g. 2026-04-12-anquria-63-macambo.md (no path needed).

DeepL key: set DEEPL_AUTH_KEY env var, or create .deepl_key at repo root.

Install dependencies first:
  pip install -r requirements.txt
"""

import argparse
import os
import re
import sys
from pathlib import Path

import yaml

try:
    import deepl
except ImportError:
    sys.exit("Missing dependency: pip install deepl")


ROOT = Path(__file__).resolve().parent.parent

# These labels and headings are fixed per language — never sent to DeepL.
# The numbers are extracted from the French source and dropped in verbatim.
SCORE_LABELS = {
    "fr": ["_Unicité_",      "_Finesse_", "_Confort_",        "_Intensité_",   "_Impression générale_"],
    "en": ["_Uniqueness_",   "_Finesse_", "_Comfort_",        "_Intensity_",   "_General impression_"],
    "es": ["_Originalidad_", "_Fineza_",  "_Reconfortante_",  "_Intensidad_",  "_Impresión general_"],
}
SCORE_HEADING = {"fr": "### Notes",      "en": "### Evaluation",  "es": "### Evaluación"}
SCORE_FINAL   = {"fr": "**Note finale**","en": "**Final evaluation**", "es": "**Evaluación final**"}

# EN-US and ES are the standard DeepL target codes for these languages.
DEEPL_TARGET = {"en": "EN-US", "es": "ES"}

# DeepL sometimes mistranslates domain-specific tags. Corrections applied after translation.
TAG_CORRECTIONS = {
    "en": {"Black": "Dark"},
    "es": {},
}

# Matches the entire scores block: heading + labelled lines + final score.
# Anchored to handle any spacing/trailing whitespace on score lines.
_SCORE_RE = re.compile(
    r"###[ \t]+\S[^\n]*\n+"            # "### Notes" (or any heading)
    r"(?:_[^_\n]+_[ \t]*:[^\n]+\n+)+"  # "_Label_: value  " lines
    r"\*\*[^\n*]+\*\*[ \t]*:[ \t]*[\d.][ \d.]*/[ \t]*25[^\n]*",  # "**Note finale**: X/25"
    re.MULTILINE,
)


# ── YAML helpers ─────────────────────────────────────────────────────────────

class _FrontMatterDumper(yaml.Dumper):
    """Dumps lists in flow style ([a, b]) to match the original post format."""
    pass

_FrontMatterDumper.add_representer(
    list,
    lambda dumper, data: dumper.represent_sequence(
        "tag:yaml.org,2002:seq", data, flow_style=True
    ),
)

def split_front_matter(text: str) -> tuple[dict, str]:
    """Split a Jekyll post into (front_matter_dict, body_text)."""
    if not text.startswith("---\n"):
        return {}, text
    parts = text.split("---\n", 2)
    if len(parts) < 3:
        return {}, text
    fm = yaml.safe_load(parts[1]) or {}
    return fm, parts[2]


def dump_front_matter(fm: dict) -> str:
    return yaml.dump(fm, Dumper=_FrontMatterDumper, allow_unicode=True, default_flow_style=False, sort_keys=False)


def reassemble(fm: dict, body: str) -> str:
    return f"---\n{dump_front_matter(fm)}---\n\n{body.strip()}\n"


# ── Score block helpers ───────────────────────────────────────────────────────

def extract_scores(body: str) -> tuple[str, str | None, str]:
    """Return (before, scores_block_or_None, after)."""
    m = _SCORE_RE.search(body)
    if not m:
        return body, None, ""
    return body[: m.start()], m.group(0), body[m.end() :]


def parse_score_numbers(scores_block: str) -> tuple[list[str], str]:
    """Return (list of 5 criterion values, final string like '24/25')."""
    values = re.findall(r"_[^_\n]+_[ \t]*:[ \t]*([\d.]+)", scores_block)
    m = re.search(r"\*\*[^\n*]+\*\*[ \t]*:[ \t]*([\d.]+[ \t]*/[ \t]*25)", scores_block)
    final = m.group(1).replace(" ", "") if m else "?/25"
    return values, final


def build_scores_block(lang: str, values: list[str], final: str) -> str:
    lines = [SCORE_HEADING[lang], ""]
    for label, value in zip(SCORE_LABELS[lang], values):
        lines.append(f"{label}: {value}  ")
    lines += ["", f"{SCORE_FINAL[lang]}: {final}"]
    return "\n".join(lines)


# ── DeepL helper ─────────────────────────────────────────────────────────────

def load_api_key() -> str:
    key = os.environ.get("DEEPL_AUTH_KEY") or os.environ.get("DEEPL_API_KEY", "")
    if not key:
        key_file = ROOT / ".deepl_key"
        if key_file.exists():
            key = key_file.read_text().strip()
    return key


def batch_translate(translator: deepl.Translator, texts: list[str], target_lang: str) -> list[str]:
    """Translate a list of strings in a single API call."""
    results = translator.translate_text(texts, source_lang="FR", target_lang=target_lang)
    return [r.text for r in results]


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Translate French Jekyll posts via DeepL.")
    parser.add_argument("-n", "--dry-run", action="store_true", help="List files without translating")
    parser.add_argument("-l", "--langs",   default="en,es",     help="Target languages (default: en,es)")
    parser.add_argument("files", nargs="*", metavar="FILE",
                        help="Specific filenames to retranslate (e.g. 2026-04-12-foo.md). "
                             "If omitted, only untranslated posts are processed.")
    args = parser.parse_args()

    target_langs = [l.strip() for l in args.langs.split(",") if l.strip()]
    unknown = [l for l in target_langs if l not in DEEPL_TARGET]
    if unknown:
        sys.exit(f"ERROR: unsupported language(s): {', '.join(unknown)}. Supported: {', '.join(DEEPL_TARGET)}")

    api_key = load_api_key()
    if not api_key and not args.dry_run:
        sys.exit("ERROR: set DEEPL_AUTH_KEY env var or create .deepl_key at repo root.")

    translator = deepl.Translator(api_key) if not args.dry_run else None

    source_dir = ROOT / "_i18n" / "fr" / "_posts"
    if not source_dir.exists():
        sys.exit(f"ERROR: source directory not found: {source_dir}")

    # If specific files were given, resolve them; otherwise process all source posts.
    if args.files:
        src_paths = []
        for name in args.files:
            p = source_dir / Path(name).name  # accept bare filename or full path
            if not p.exists():
                sys.exit(f"ERROR: {p} not found in {source_dir}")
            src_paths.append(p)
    else:
        src_paths = sorted(source_dir.glob("*.md"))

    translated: list[Path] = []
    skipped:    list[Path] = []

    for src_path in src_paths:
        content = src_path.read_text()
        fm, body = split_front_matter(content)
        before, scores_block, after = extract_scores(body)

        for lang in target_langs:
            dest_dir = ROOT / "_i18n" / lang / "_posts"
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest_path = dest_dir / src_path.name

            # Skip only when processing all posts (no specific files given).
            if dest_path.exists() and not args.files:
                skipped.append(dest_path)
                continue

            if args.dry_run:
                translated.append(dest_path)
                continue

            # Build a single batch of everything that needs translating.
            # We track each item's position so we can unpack after the call.
            batch: list[str] = []
            idx: dict[str, int | slice] = {}

            title = fm.get("title", "")
            if title:
                idx["title"] = len(batch)
                batch.append(str(title))

            tags = fm.get("tags") or []
            if isinstance(tags, list) and tags:
                idx["tags"] = slice(len(batch), len(batch) + len(tags))
                batch.extend(str(t) for t in tags)

            if before.strip():
                idx["before"] = len(batch)
                batch.append(before)

            if after.strip():
                idx["after"] = len(batch)
                batch.append(after)

            results = batch_translate(translator, batch, DEEPL_TARGET[lang])

            # Rebuild front matter with translated fields.
            new_fm = {k: v for k, v in fm.items()
                      if k not in ("translated_from", "translated_at", "translated_to")}
            if "title" in idx:
                new_fm["title"] = results[idx["title"]]
            if "tags" in idx:
                corrections = TAG_CORRECTIONS.get(lang, {})
                new_fm["tags"] = [corrections.get(t, t) for t in results[idx["tags"]]]
            new_fm["needs_review"] = True

            # Rebuild body: translated prose + fixed scores block.
            translated_before = results[idx["before"]].strip() if "before" in idx else ""
            translated_after  = results[idx["after"]].strip()  if "after"  in idx else ""

            if scores_block:
                values, final = parse_score_numbers(scores_block)
                new_scores = build_scores_block(lang, values, final)
            else:
                new_scores = ""

            body_parts = [p for p in [translated_before, new_scores, translated_after] if p]
            new_body = "\n\n".join(body_parts)

            dest_path.write_text(reassemble(new_fm, new_body))
            translated.append(dest_path)
            print(f"  [{lang}] {src_path.name}")

    print(f"\nTranslated {len(translated)} file(s) ({', '.join(target_langs)})")
    if skipped:
        print(f"Skipped {len(skipped)} existing file(s) — use --force to retranslate")


if __name__ == "__main__":
    main()
