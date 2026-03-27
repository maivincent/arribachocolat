#!/usr/bin/env python3
"""
Translate French posts to other languages using DeepL (Python port).

Usage:
  DEEPL_AUTH_KEY=<key> python3 bin/translate_posts.py
  python3 bin/translate_posts.py               # reads key from .deepl_key if present
  python3 bin/translate_posts.py --dry-run     # list files that would be translated
  python3 bin/translate_posts.py --langs en,es

Notes:
- This script intentionally does not overwrite existing translated files.
- It preserves numeric grades and applies localized labels.
"""

import argparse
import os
import sys
import json
import time
import re
from urllib import request, parse, error
from pathlib import Path

try:
    import yaml
    HAS_YAML = True
except Exception:
    HAS_YAML = False

DEFAULT_LANGS = ["en", "es"]
ROOT = Path(__file__).resolve().parent.parent
API_URL = os.environ.get('DEEPL_API_URL', 'https://api-free.deepl.com/v2/translate')

def read_api_key():
    key = os.environ.get('DEEPL_AUTH_KEY') or os.environ.get('DEEPL_API_KEY')
    key_path = ROOT / '.deepl_key'
    if not key and key_path.exists():
        key = key_path.read_text(encoding='utf-8').strip()
    if not key:
        return None
    return key

def split_front_matter(content):
    if not content.startswith('---\n'):
        return None, content
    parts = re.split(r'^---\s*\n', content, maxsplit=2, flags=re.MULTILINE)
    if len(parts) >= 3:
        # parts[1] is yaml, parts[2] is body
        return parts[1], parts[2]
    return None, content

GRADE_LINE_RE = re.compile(r':\s*[0-9]+(?:\.[0-9]+)?')

def extract_grades_block(text):
    lines = text.splitlines(True)
    n = len(lines)
    start = None
    end = None
    for i in range(n):
        if GRADE_LINE_RE.search(lines[i]):
            if start is None:
                start = i
            end = i
        elif start is not None and end is not None and i == end + 1:
            break

    if start is None:
        return text, [], ''

    # If a markdown heading (e.g. "### Notes") appears immediately above the grades block,
    # include it in the grades chunk so that it is not sent to DeepL.
    for candidate in range(max(0, start - 2), start):
        if re.match(r'^\s*#+\s+', lines[candidate]):
            start = candidate
            break

    before = ''.join(lines[:start])
    grades = [ln.rstrip('\n') for ln in lines[start:end+1]]
    after = ''
    return before, grades, after

def deepl_translate(text, target_lang, source_lang, api_key, api_url, dry_run=False):
    if not text:
        return ''
    if dry_run:
        print(f"[dry-run] translate to {target_lang} ({len(text)} chars)")
        return ''
    data = {
        'text': text,
        'source_lang': source_lang,
        'target_lang': target_lang.upper(),
        'preserve_formatting': '1',
        'split_sentences': 'nonewlines'
    }
    encoded = parse.urlencode(data).encode('utf-8')
    req = request.Request(api_url, data=encoded, method='POST')
    req.add_header('Authorization', f'DeepL-Auth-Key {api_key}')
    req.add_header('Content-Type', 'application/x-www-form-urlencoded')
    try:
        with request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode('utf-8')
            j = json.loads(body)
            texts = [t.get('text','') for t in j.get('translations', [])]
            return '\n\n'.join(texts)
    except error.HTTPError as he:
        raise RuntimeError(f"DeepL API error {he.code}: {he.read().decode('utf-8')}")
    except Exception as e:
        raise

def find_template_labels(root, lang):
    dest_dir = Path(root) / '_i18n' / lang / '_posts'
    if not dest_dir.exists():
        return None
    for p in sorted(dest_dir.glob('*.md')):
        content = p.read_text(encoding='utf-8')
        _fm, body = split_front_matter(content)
        before, grades, after = extract_grades_block(body)
        if grades:
            labels = []
            for line in grades:
                # skip heading lines and empty lines
                if re.match(r'^\s*#+\s+', line) or not line.strip():
                    continue
                if ':' not in line:
                    continue
                parts = line.split(':', 1)
                labels.append(parts[0].strip())
            if labels:
                return labels
    return None

def sanitize_label(lbl):
    s = lbl.strip()
    # remove surrounding underscores or asterisks
    s = re.sub(r'^[*_]+|[*_]+$', '', s)
    s = s.rstrip(':')
    return s.strip()

FALLBACK_LABELS = {
    'en': ['Uniqueness', 'Finesse', 'Comfort', 'Intensity', 'Overall impression'],
    'es': ['Originalidad', 'Fineza', 'Reconfortante', 'Intensidad', 'Impresión general']
}

FINAL_LABEL = {'en': '**Final evaluation**', 'es': '**Nota final**'}
HEADING = {'en': '### Evaluation', 'es': '### Evaluación'}

def build_grades_block(template_labels, source_grades_lines, lang=None):
    if not source_grades_lines:
        return ''

    # strip heading lines (e.g. "### Notes") from the source grades block before parsing
    lines = [ln for ln in source_grades_lines]
    while lines and re.match(r'^\s*#+\s+', lines[0]):
        lines.pop(0)

    # extract numbers and final fraction
    numbers = []
    final_fraction = None
    for ln in lines:
        if re.match(r'^\s*#+\s+', ln):
            continue
        if '**' in ln:
            m = re.search(r'([0-9]+(?:\.[0-9]+)?\s*/\s*25)', ln)
            if m:
                final_fraction = m.group(1).replace(' ', '')
            continue
        m = re.search(r'([0-9]+(?:\.[0-9]+)?)', ln)
        if m:
            numbers.append(m.group(1))

    labels = template_labels if isinstance(template_labels, list) else None
    # infer lang fallback
    chosen = labels or FALLBACK_LABELS.get(lang, FALLBACK_LABELS['en'])
    heading = HEADING.get(lang, HEADING['en'])
    final_label = FINAL_LABEL.get(lang, FINAL_LABEL['en'])

    out = [heading]
    for idx, lbl in enumerate(chosen[:5]):
        clean = sanitize_label(lbl)
        val = numbers[idx] if idx < len(numbers) else ''
        out.append(f"_{clean}_: {val}  ")

    if final_fraction:
        out.append('\n' + f"{final_label}: {final_fraction}")
    else:
        if all(re.match(r'^\d+(?:\.\d+)?$', n) for n in numbers if n):
            total = sum(float(n) for n in numbers if n)
            total_s = str(int(total)) if total.is_integer() else str(total)
            out.append('\n' + f"{final_label}: {total_s}/25")
        else:
            out.append('\n' + f"{final_label}:")

    return '\n'.join(out)

def parse_front_matter_yaml(fm_text):
    if not fm_text:
        return {}
    if HAS_YAML:
        try:
            return yaml.safe_load(fm_text) or {}
        except Exception:
            pass
    # fallback: crude parsing for title/tags/categories
    fm = {}
    for line in fm_text.splitlines():
        m = re.match(r'^(title):\s*(?:"([^"]+)")?', line)
        if m:
            # handled below more robustly
            pass
        # try key: value
        m2 = re.match(r'^(\w+):\s*(.*)$', line)
        if m2:
            k = m2.group(1)
            v = m2.group(2).strip()
            if v.startswith('[') and v.endswith(']'):
                items = [x.strip().strip('"') for x in v[1:-1].split(',') if x.strip()]
                fm[k] = items
            else:
                fm[k] = v.strip('"')
    return fm

def emit_front_matter(fm_dict, title_val=None):
    out_lines = ['---']
    if title_val:
        escaped = title_val.replace('"', '\\"')
        out_lines.append(f'title: "{escaped}"')
    # tags
    tags = fm_dict.pop('tags', None)
    if tags:
        if isinstance(tags, list):
            items = ', '.join(f'"{t}"' for t in tags)
            out_lines.append(f'tags: [{items}]')
        else:
            out_lines.append(f'tags: ["{tags}"]')
    cats = fm_dict.pop('categories', None)
    if cats:
        if isinstance(cats, list):
            items = ', '.join(f'"{c}"' for c in cats)
            out_lines.append(f'categories: [{items}]')
        else:
            out_lines.append(f'categories: ["{cats}"]')

    # dump remaining keys if yaml available
    if fm_dict:
        if HAS_YAML:
            dumped = yaml.safe_dump(fm_dict, sort_keys=False)
            # safe_dump may include leading '---\n', ensure no duplication
            dumped = re.sub(r'^---\n', '', dumped)
            out_lines.append(dumped.rstrip('\n'))
        else:
            for k, v in fm_dict.items():
                out_lines.append(f"{k}: {v}")

    out_lines.append('---')
    return '\n'.join(out_lines) + '\n\n'

def main():
    p = argparse.ArgumentParser()
    p.add_argument('-n', '--dry-run', action='store_true', help='Show which files would be translated')
    p.add_argument('-l', '--langs', default=','.join(DEFAULT_LANGS), help='Comma-separated target langs')
    args = p.parse_args()

    options = {
        'dry_run': args.dry_run,
        'langs': [l.strip() for l in args.langs.split(',') if l.strip()],
        'source_lang': 'FR'
    }

    api_key = read_api_key()
    if not api_key and not options['dry_run']:
        print(f"ERROR: Set DEEPL_AUTH_KEY or create {ROOT / '.deepl_key'} with your key.")
        sys.exit(1)

    source_dir = ROOT / '_i18n' / 'fr' / '_posts'
    if not source_dir.exists():
        print(f"ERROR: source directory not found: {source_dir}")
        sys.exit(1)

    translated = []
    skipped = []

    for src_path in sorted(source_dir.glob('*.md')):
        filename = src_path.name
        content = src_path.read_text(encoding='utf-8')
        fm_text, body = split_front_matter(content)
        front_matter = parse_front_matter_yaml(fm_text)

        for lang in options['langs']:
            dest_dir = ROOT / '_i18n' / lang / '_posts'
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest_path = dest_dir / filename
            if dest_path.exists():
                skipped.append(str(dest_path))
                continue

            if options['dry_run']:
                translated.append(str(dest_path))
                continue

            before_text, source_grades_lines, after_text = extract_grades_block(body)

            # Translate parts
            translated_before = '' if not before_text.strip() else deepl_translate(before_text, lang, options['source_lang'], api_key, API_URL, options['dry_run'])
            translated_after = '' if not after_text.strip() else deepl_translate(after_text, lang, options['source_lang'], api_key, API_URL, options['dry_run'])

            # Build grades block
            template_labels = find_template_labels(ROOT, lang)
            grades_block = '' if not source_grades_lines else build_grades_block(template_labels, source_grades_lines, lang)

            translated_body_parts = [p for p in [translated_before.strip(), grades_block.strip(), translated_after.strip()] if p]
            translated_body = '\n\n'.join(translated_body_parts) + '\n' if translated_body_parts else ''

            # Title
            translated_title = None
            if isinstance(front_matter, dict) and 'title' in front_matter:
                translated_title = deepl_translate(str(front_matter['title']), lang, options['source_lang'], api_key, API_URL, options['dry_run']).strip()

            # Tags: handle mapping for 'Noir'
            translated_tags = None
            if isinstance(front_matter, dict) and front_matter.get('tags'):
                tags = front_matter.get('tags') if isinstance(front_matter.get('tags'), list) else [str(front_matter.get('tags'))]
                out_tags = []
                for t in tags:
                    t = str(t).strip()
                    if not t:
                        continue
                    if t.lower() == 'noir':
                        mapped = 'Negro' if lang == 'es' else ('Dark' if lang == 'en' else t)
                        out_tags.append(mapped)
                    else:
                        out_tags.append(deepl_translate(t, lang, options['source_lang'], api_key, API_URL, options['dry_run']).strip())
                translated_tags = out_tags

            # Emit front matter (don't include translation metadata)
            fm_copy = dict(front_matter) if isinstance(front_matter, dict) else {}
            if 'title' in fm_copy:
                del fm_copy['title']
            if 'tags' in fm_copy:
                del fm_copy['tags']
            if 'categories' in fm_copy:
                # keep categories in fm_copy, emit below
                pass

            fm_emit = fm_copy
            # prefer translated_tags when emitting
            if translated_tags is not None:
                fm_emit['tags'] = translated_tags
            # categories unchanged

            output = emit_front_matter(fm_emit, title_val=translated_title or front_matter.get('title') if isinstance(front_matter, dict) else None)
            output += translated_body
            dest_path.write_text(output, encoding='utf-8')
            translated.append(str(dest_path))

    print(f"Translated {len(translated)} files ({', '.join(DEFAULT_LANGS)})")
    for p in translated:
        print(f"  - {p}")
    if skipped:
        print(f"Skipped {len(skipped)} existing files")

if __name__ == '__main__':
    main()
