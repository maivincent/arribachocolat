#!/usr/bin/env bash

# Deploy the built Jekyll site to the gh-pages branch via a git worktree.
# This keeps the source branch (main) clean and avoids checking out gh-pages in the main working tree.

set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <commit message>"
  exit 1
fi

commit_message="$1"

# Determine repository root and source branch (prefer main, fall back to master)
repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

source_branch=main
if ! git show-ref --verify --quiet refs/heads/$source_branch; then
  source_branch=master
fi

# Ensure we're on the source branch while building
git checkout "$source_branch"

# Build into a temporary directory so we can safely create a worktree in _site
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
bundle exec jekyll build --destination "$build_dir"

# Ensure _site is a git worktree on gh-pages
worktree_dir="$repo_root/_site"
if [[ ! -f "$worktree_dir/.git" ]]; then
  echo "Setting up gh-pages worktree at $worktree_dir"
  rm -rf "$worktree_dir"
  git worktree add -B gh-pages "$worktree_dir" origin/gh-pages
fi

# Sync built site into the worktree (preserves .git)
rsync -a --delete --exclude='.git' "$build_dir"/ "$worktree_dir"/

cd "$worktree_dir"

echo "www.arribachocolat.ca" >> CNAME

git add --all
if git diff --cached --quiet; then
  echo "No changes to deploy."
else
  git commit -m "$commit_message"
  git push origin gh-pages
fi

# Return to source branch
cd "$repo_root"
git checkout "$source_branch"

echo "Successfully built and pushed gh-pages to Github."
