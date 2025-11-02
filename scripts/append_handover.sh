#!/usr/bin/env bash
set -euo pipefail

# Append a UTC timestamp line to handover/SBX_Handover.md, commit, and push.
HANDOVER_FILE="handover/SBX_Handover.md"

if [ ! -d "$(dirname "$HANDOVER_FILE")" ]; then
  mkdir -p "$(dirname "$HANDOVER_FILE")"
fi

echo "SBX handover sync — $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> "$HANDOVER_FILE"

git add "$HANDOVER_FILE"
git commit -m "Appended SBX handover update" || echo "No changes to commit"
git push origin main
