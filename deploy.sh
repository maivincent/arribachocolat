#!/usr/bin/env bash

if [[ -z "$1" ]]; then
  echo "Please enter a git commit message"
  exit
fi

# Commit and push changes in main branch first
echo "Committing and pushing changes to main branch..."
git add --all && \
git reset HEAD _site && \
git commit -m "$1" || true && \
git push origin main

# Generate grades data from post content before building
echo "Generating grades data..."
ruby bin/generate_grades.rb

# Build Jekyll site
echo "Building Jekyll site..."
bundle exec jekyll build

# Commit and push built site to gh-pages
cd _site && \
git checkout gh-pages && \
echo "www.arribachocolat.ca" >> CNAME && \
git add --all && \
git commit -m "$1" || true && \
git push origin gh-pages && \
cd .. && \
echo "Successfully built and pushed gh-pages to Github."
