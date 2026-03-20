#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d .git ]]; then
  git init
fi

git add .
if ! git diff --cached --quiet; then
  git commit -m "chore: initialize FrostBar scaffold"
fi

echo "Bootstrap complete."
