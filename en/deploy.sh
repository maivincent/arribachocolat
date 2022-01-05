#!/usr/bin/env bash

if [[ -z "$1" ]]; then
  echo "Please enter a git commit message"
  exit
fi

cd _site && \
git add . && \
git commit -m "$1" && \
git push origin gh-pages && \
cd .. && \
echo "Successfully built and pushed gh-pages to Github."
