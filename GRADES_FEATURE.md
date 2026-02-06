# Arriba Chocolat - Grade-Based Sorting Feature

## Overview

You now have a **"Find by Grade"** tab at `/grades/` that displays all chocolate posts sorted by their final evaluation score.

## How It Works

### 1. Grade Data Generation
- Run `ruby bin/generate_grades.rb` (or automatically via `./deploy.sh`)
- This script scans all post markdown files and extracts the final evaluation score
- Creates `_data/grades.yml` with posts organized into grade buckets

### 2. Grade Buckets
Posts are grouped by the **floor of their score**:
- **25** - Perfect or near-perfect scores (25–25.9)
- **24** - Scores 24–24.9
- **23** - Scores 23–23.9
- **22** - Scores 22–22.9  
- **21** - Scores 21–21.9
- **20** - Scores 20–20.9
- **<20** - Scores below 20

### 3. Layout & Templates
- New file: `grades.md` - archive page using `archive-taxonomies` layout
- Updated layout: `_layouts/archive-taxonomies.html` - detects `page.type: grades` and renders from `site.data.grades`
- The layout already supported "Find by Brand" (categories) and "Find by Flavor" (tags), so grades fit naturally into the same template

### 4. Localization
The grade extraction regex supports:
- **English**: "Final evaluation"
- **Spanish**: "Evaluación final"
- **French**: "Note finale"

The script also strips Markdown emphasis (`**`, `_`, etc.) for robust parsing.

## Usage

### For Development
```bash
# Generate grades data
ruby bin/generate_grades.rb

# Build locally
bundle exec jekyll build

# Or serve with local preview
bundle exec jekyll serve
```

### For Deployment
```bash
./deploy.sh "Added new chocolate reviews"
```
The deploy script automatically regenerates grades before pushing.

## Statistics

Currently **625 posts** are indexed across grade buckets, with distribution:
- 25: 32 posts
- 24: 83 posts
- 23: 120 posts
- 22: 168 posts
- 21: 86 posts
- 20: 49 posts
- <20: 87 posts

## Files Created/Modified

### Created
- `bin/generate_grades.rb` - Grade data generator script
- `bin/README.md` - Documentation for the generator
- `grades.md` - Archive page entry point
- `_data/grades.yml` - Generated data file (created by script)

### Modified
- `_layouts/archive-taxonomies.html` - Added grades rendering logic
- `deploy.sh` - Added grade generation step

### Removed
- Unused plugin files (Jekyll hooks/generators didn't work well with multilanguage plugin)

## Notes

- The grade generation must run **before** each Jekyll build (included in deploy.sh)
- The YAML data file (`_data/grades.yml`) should be regenerated whenever posts are added or scores are updated
- The feature respects the same multilingual structure as brands and flavors, so `/en/grades/`, `/es/grades/`, `/fr/grades/` all work automatically
