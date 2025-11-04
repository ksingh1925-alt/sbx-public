#!/usr/bin/env bash
set -euo pipefail

# Bootstrapping helper for new clones. Creates handover files if missing and makes an initial commit when in a git repo.
HANDOVER_DIR="handover"
HANDOVER_FILE="$HANDOVER_DIR/SBX_Handover.md"
STATUS_FILE="$HANDOVER_DIR/status.json"

mkdir -p "$HANDOVER_DIR"
if [ ! -f "$HANDOVER_FILE" ]; then
  echo "SBX handover sync — $(date -u +"%Y-%m-%d %H:%M:%S UTC")" > "$HANDOVER_FILE"
  echo "Created $HANDOVER_FILE"
fi

if [ ! -f "$STATUS_FILE" ]; then
  cat > "$STATUS_FILE" <<EOF
{
  "timestamp_utc": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
  "commit": "",
  "file": "$HANDOVER_FILE",
  "run_id": "",
  "runner_hostname": "",
  "workflow_url": ""
}
EOF
  echo "Created $STATUS_FILE"
fi

# If this is a git repo, add and commit the new files if there are changes
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add "$HANDOVER_FILE" "$STATUS_FILE" || true
  if git diff --staged --quiet; then
    echo "No changes to commit"
  else
    git commit -m "chore: initialize handover files"
    echo "Committed initial handover files"
  fi
else
  echo "Not a git repository — created files locally. After initializing a repo, commit them manually."
fi

echo "Setup complete. You can run: scripts/append_handover.sh --dry-run to test, or make handover-sync to append and push."
