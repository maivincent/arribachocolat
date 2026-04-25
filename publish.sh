#!/usr/bin/env bash
# Commit content changes, push main, then build and deploy to gh-pages.
# Usage: ./publish.sh 'commit message'

set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <commit message>"
  exit 1
fi

commit_message="$1"
repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

ruby bin/generate_grades.rb
ruby bin/generate_brand_pages.rb
git add --all
git commit -m "$commit_message"
git push
./deploy.sh "$commit_message"
