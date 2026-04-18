# Arriba Chocolat — Repository Overview

## What this site is

A trilingual (French / English / Spanish) Jekyll blog reviewing Ecuadorian fine-aroma ("fino d'aroma") chocolate bars. Each post reviews one bar with five scored criteria and a final grade out of 25.

Site URL: **www.arribachocolat.ca** (served via GitHub Pages)

---

## Two-level git structure

### Level 1 — Source repo (`main` branch)

Working directory: `~/Documents/Projects/arriba_choco/arribachocolat/`  
Remote: `git@github.com:maivincent/arribachocolat.git`  
Branch: `main`

This is where all content and code live. Other branches:
- `gh-pages` — built site (see below)
- `Translation` — feature branch for translation work
- `contents` — content-related branch

### Level 2 — `_site/` is a git worktree on `gh-pages`

`_site/` is **not** a regular subdirectory. It is a [git worktree](https://git-scm.com/docs/git-worktree) pointing at the `gh-pages` branch of the same remote. This means:

- `_site/` has its own `.git` file (not `.git/` directory — just a pointer)
- Commits inside `_site/` land on `gh-pages`, not on `main`
- `git push` from inside `_site/` pushes `gh-pages` to GitHub Pages
- The `deploy.sh` script manages this lifecycle automatically

**Never manually edit files inside `_site/`** — they are overwritten on every build.

---

## Jekyll setup

| Setting | Value |
|---|---|
| Theme | `vszhub/not-pure-poole` (remote theme) |
| Multilingual plugin | `jekyll-multiple-languages-plugin` |
| Languages | `fr`, `en`, `es` (French is canonical) |
| Pagination | 5 posts per page |
| Markdown | kramdown |

---

## Directory structure

```
arribachocolat/
├── _config.yml            # Jekyll config (languages, theme, plugins)
├── _i18n/
│   ├── fr/
│   │   ├── _posts/        # 239 French posts (canonical source)
│   │   ├── about.md
│   │   ├── cocoa.md
│   │   └── marques.md
│   ├── en/                # 231 posts — auto-translated from fr via DeepL
│   ├── es/                # 231 posts — auto-translated from fr via DeepL
│   ├── fr.yml             # UI strings in French
│   ├── en.yml             # UI strings in English
│   └── es.yml             # UI strings in Spanish
├── _layouts/
│   ├── post.html
│   ├── home.html
│   ├── page.html
│   └── archive-taxonomies.html  # powers /grades, /tags, /marques pages
├── _includes/             # partials (head, sidebar, etc.)
├── _data/
│   ├── grades.yml         # GENERATED — do not edit by hand
│   ├── navigation.yml     # top-nav links
│   ├── archive.yml
│   └── social.yml
├── _sass/                 # custom styles
├── bin/
│   ├── translate_posts.rb # DeepL translation of fr posts → en + es
│   ├── generate_grades.rb # parses post scores → _data/grades.yml
│   └── README.md
├── assets/                # images, css, js
├── _site/                 # git worktree on gh-pages (BUILT OUTPUT)
├── index.html
├── grades.md              # /grades archive page
├── tags.md                # /tags archive page
├── marques.html           # /marques archive page
├── about.html
├── categories.md
├── dates.md
├── deploy.sh              # full build + push to gh-pages
├── Gemfile / Gemfile.lock
└── mode_emploi.txt        # workflow cheatsheet
```

---

## Post format

Posts live in `_i18n/fr/_posts/` (French canonical). Filename convention:
`YYYY-MM-DD-brand-pct-flavour.md`

Front matter:
```yaml
layout: post
title: "Brand - XX% Flavour"
tags: [Noir, Gingembre]
categories: [Brand Name]
```

Body: free prose in Markdown. Ends with a structured scoring section:

```markdown
### Notes
_Unicité_: X
_Finesse_: X
_Confort_: X
_Intensité_: X
_Impression générale_: X

**Note finale**: XX/25
```

The grade regex in `generate_grades.rb` matches all three language variants of the final score label.

---

## Data pipeline

```
fr _posts (239)
    │
    ▼
bin/translate_posts.rb  ──DeepL API──►  en _posts (231) + es _posts (231)
    │
    ▼
bin/generate_grades.rb  ──parses all posts──►  _data/grades.yml
    │
    ▼
bundle exec jekyll build  ──►  _site/ (gh-pages worktree)
    │
    ▼
deploy.sh  ──git push──►  GitHub Pages (www.arribachocolat.ca)
```

**8 French posts do not yet have translations** (239 fr vs 231 en/es).

---

## Workflow (from mode_emploi.txt)

1. Write/edit posts in `_i18n/fr/_posts/`
2. `ruby bin/translate_posts.rb` — generates/updates en+es translations (needs DeepL key in `.deepl_key` or `DEEPL_AUTH_KEY` env var)
3. `ruby bin/generate_grades.rb` — regenerates `_data/grades.yml`
4. `git add --all && git commit -m 'MESSAGE'`
5. `git push` — pushes `main` to GitHub
6. `bundle exec jekyll build` — builds into `_site/`
7. `./deploy.sh 'MESSAGE'` — syncs `_site/` and pushes `gh-pages`

Steps 6–7 can be collapsed: `deploy.sh` handles the build internally.

---

## Archive / taxonomy pages

Three archive views, all using `_layouts/archive-taxonomies.html`:

| Page | Source | URL |
|---|---|---|
| By grade | `_data/grades.yml` | `/grades/` |
| By tag/flavour | Jekyll tags | `/tags/` |
| By brand | Jekyll categories | `/marques/` |

Grade buckets: `<=20`, `21`, `21.5`, `22`, `22.5`, `23`, `23.5`, `24`, `24.5`, `25`.

---

## Key constraints

- **Never edit `_site/` directly** — it is regenerated on every build.
- **`_data/grades.yml` is generated** — edit posts, then re-run `generate_grades.rb`.
- **French posts are canonical** — en/es are derived; editing them directly will be overwritten by the next translation run unless `--force` is avoided.
- **DeepL key required** for translation (stored in `.deepl_key`, not tracked by git).
- **Deploy must be from `main` with a clean working tree** (enforced by `deploy.sh`).
