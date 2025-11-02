#!/usr/bin/env bash
set -euo pipefail

# Usage: scripts/append_handover.sh [--dry-run] [--branch <name>]
# --dry-run : don't commit or push, just show what would happen
# --branch  : target branch to push (default: main)

HANDOVER_FILE="handover/SBX_Handover.md"
STATUS_FILE="handover/status.json"
LOCK_FILE="/tmp/sbx_handover.lock"

DRY_RUN=0
BRANCH="main"

print_usage() {
  echo "Usage: $0 [--dry-run] [--branch <name>]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --branch)
      if [[ -z "${2-}" ]]; then
        echo "--branch requires an argument" >&2
        print_usage
        exit 2
      fi
      BRANCH="$2"
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      print_usage
      exit 2
      ;;
  esac
done

echo "[info] target branch: $BRANCH"
echo "[info] dry-run: $DRY_RUN"

mkdir -p "$(dirname "$HANDOVER_FILE")"

# Acquire flock to prevent concurrent runs
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "[error] another append operation is in progress (lock: $LOCK_FILE)" >&2
  exit 1
fi

TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
LINE="SBX handover sync — $TIMESTAMP"

echo "[info] appending line: $LINE"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] would append to $HANDOVER_FILE: $LINE"
  echo "[dry-run] would create/overwrite $STATUS_FILE with timestamp and commit info"
  echo "{\"timestamp_utc\": \"$TIMESTAMP\", \"commit\": \"<would-commit>\", \"file\": \"$HANDOVER_FILE\"}"
  echo "[dry-run] would git add/commit and push to branch: $BRANCH"
  exit 0
fi

echo "$LINE" >> "$HANDOVER_FILE"

# Ensure we are on the desired branch (create if necessary)
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  git checkout "$BRANCH"
else
  git checkout -b "$BRANCH"
fi

echo "[info] staging $HANDOVER_FILE"
git add "$HANDOVER_FILE"

COMMIT_MSG="SBX handover sync: $TIMESTAMP"
if git commit -m "$COMMIT_MSG"; then
  echo "[info] committed appended line"
else
  echo "[info] no changes to commit (nothing appended?)"
fi

# Compute short hash of the new commit (this is the final commit that added the line)
COMMIT_SHORT=$(git rev-parse --short HEAD || echo "")

# Additional traceability fields (available in GitHub Actions environment)
RUN_ID=${GITHUB_RUN_ID-}
RUNNER_HOSTNAME="$(hostname 2>/dev/null || true)"
REPO=${GITHUB_REPOSITORY-}
if [[ -z "$REPO" ]]; then
  # try to infer from origin remote
  REPO=$(git config --get remote.origin.url || true)
  # convert git URL to owner/repo if possible
  REPO=$(echo "$REPO" | sed -n 's#.*/\([^/]*\/[^/]*\)\(.git\)*$#\1#p')
fi
WORKFLOW_URL=""
if [[ -n "${RUN_ID-}" && -n "$REPO" ]]; then
  WORKFLOW_URL="https://github.com/${REPO}/actions/runs/${RUN_ID}"
fi

echo "[info] writing status file $STATUS_FILE with commit $COMMIT_SHORT and run_id ${RUN_ID:-}" 
cat > "$STATUS_FILE" <<EOF
{
  "timestamp_utc": "$TIMESTAMP",
  "commit": "${COMMIT_SHORT}",
  "file": "$HANDOVER_FILE",
  "run_id": "${RUN_ID:-}",
  "runner_hostname": "${RUNNER_HOSTNAME:-}",
  "workflow_url": "${WORKFLOW_URL:-}"
}
EOF

git add "$STATUS_FILE"
if git commit -m "Update handover status: $TIMESTAMP"; then
  echo "[info] committed status.json"
else
  echo "[info] no changes to commit for status.json"
fi

echo "[info] pushing to origin/$BRANCH"
git push origin "$BRANCH"

echo "[info] done. appended: $LINE"
echo "[info] status: $STATUS_FILE (commit: $COMMIT_SHORT)"

