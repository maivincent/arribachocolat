# Arriba Chocolat - Grade Generation Helper

This script generates the grades data file (`_data/grades.yml`) from all post markdown files.

## Usage

```bash
ruby bin/generate_grades.rb
```

## What it does

1. Scans all post markdown files in `_i18n/*/_ posts/`
2. Extracts the "Final evaluation" score (or localized equivalent) from each post
3. Buckets posts by grade:
   - 25, 24, 23, 22, 21, 20 (exact floor of the score)
   - `<20` (for scores below 20)
4. Generates `_data/grades.yml` with post titles, URLs, and dates

## When to run

- **Before building locally**: `ruby bin/generate_grades.rb && bundle exec jekyll build`
- **Before deploying**: Run `./deploy.sh <message>` which automatically calls this script
- Whenever posts are added/updated: regenerate the grades file

## Localization

The script recognizes the following final evaluation labels:
- English: "Final evaluation"
- Spanish: "Evaluación final"
- French: "Note finale"
- And other variants with or without emphasis markers (`**`, `_`, etc.)
