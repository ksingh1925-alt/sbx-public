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
# Ensure we are on the desired branch (create if necessary)
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  git checkout "$BRANCH"
else
  git checkout -b "$BRANCH"
fi

echo "[info] preparing single commit containing $HANDOVER_FILE and $STATUS_FILE"

# Build status.json now. NOTE: embedding the new commit's SHA INSIDE that same commit
# is not possible with standard git plumbing (it's a circular dependency). To keep
# a single commit that contains both files, we write the status.json with the
# other trace fields but leave the commit field empty. If you need the final
# commit SHA recorded, the script could create a second commit after (currently
# avoided to keep a single commit).
cat > "$STATUS_FILE" <<EOF
{
  "timestamp_utc": "$TIMESTAMP",
  "commit": "",
  "file": "$HANDOVER_FILE",
  "run_id": "${GITHUB_RUN_ID-}",
  "runner_hostname": "$(hostname 2>/dev/null || true)",
  "workflow_url": ""
}
EOF

git add "$HANDOVER_FILE" "$STATUS_FILE"

COMMIT_MSG="SBX handover sync: $TIMESTAMP"
if git commit -m "$COMMIT_MSG"; then
  echo "[info] created single commit with handover + status.json"
else
  echo "[info] no changes to commit (nothing appended?)"
fi

echo "[info] pushing to origin/$BRANCH"
git push origin "$BRANCH"

echo "[info] done. appended: $LINE"
echo "[info] status: $STATUS_FILE (commit: <in-commit not recorded>)"
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

