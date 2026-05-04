#!/usr/bin/env python3
"""
Extract brand descriptions from _i18n/{lang}/marques.md files and write
individual files to info_marques/{lang}/{slug}.md.

Run once (or re-run if marques.md is updated).
"""

import os
import re
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Known mismatches between heading text and brand stub slug
MANUAL_OVERRIDES = {
    'paccari': 'pacari',
    'taeone': 'teaone',
    'minka-gourmet-chocolate': 'minka',
    'la-leyenda-del-chocolate': 'leyenda',
    'chaman-ecuador': 'chaman',
    'choco-cumi': 'chococumi',
    'tsatsayaku': None,  # no brand stub — skip
}


def slugify(name):
    normalized = unicodedata.normalize('NFD', name)
    name = ''.join(c for c in normalized if unicodedata.category(c) != 'Mn')
    name = name.lower()
    name = re.sub(r'[^a-z0-9]+', '-', name)
    return name.strip('-')


def get_brand_slugs():
    brands_dir = os.path.join(ROOT, 'brands')
    return {os.path.splitext(f)[0] for f in os.listdir(brands_dir) if f.endswith('.md')}


def parse_marques(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    sections = re.split(r'^### ', content, flags=re.MULTILINE)
    result = {}
    for section in sections[1:]:
        lines = section.strip().split('\n', 1)
        heading = lines[0].strip()
        body = lines[1].strip() if len(lines) > 1 else ''
        # Truncate at any ## section header (not a brand — just a grouping label)
        body = re.split(r'^## ', body, maxsplit=1, flags=re.MULTILINE)[0].strip()
        result[heading] = body
    return result


def main():
    brand_slugs = get_brand_slugs()
    langs = ['fr', 'en', 'es']

    matched = {}
    unmatched = []

    for lang in langs:
        marques_path = os.path.join(ROOT, '_i18n', lang, 'marques.md')
        sections = parse_marques(marques_path)

        for heading, content in sections.items():
            raw_slug = slugify(heading)
            slug = MANUAL_OVERRIDES.get(raw_slug, raw_slug)

            if slug is None:
                if lang == 'fr':
                    unmatched.append(f"SKIPPED: '{heading}' (manually excluded)")
                continue

            if slug not in brand_slugs:
                if lang == 'fr':
                    unmatched.append(f"NO MATCH: '{heading}' → '{slug}'")
                continue

            if slug not in matched:
                matched[slug] = {}
            matched[slug][lang] = content

    for slug, lang_contents in matched.items():
        for lang, content in lang_contents.items():
            dir_path = os.path.join(ROOT, 'info_marques', lang)
            os.makedirs(dir_path, exist_ok=True)
            filepath = os.path.join(dir_path, f'{slug}.md')
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content + '\n')

    print(f"\nExtracted {len(matched)} brand descriptions:")
    for slug in sorted(matched.keys()):
        langs_written = sorted(matched[slug].keys())
        print(f"  {slug}: {', '.join(langs_written)}")

    if unmatched:
        print(f"\nUnmatched/skipped headings:")
        for msg in unmatched:
            print(f"  {msg}")


if __name__ == '__main__':
    main()
