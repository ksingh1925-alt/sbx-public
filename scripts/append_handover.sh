#!/usr/bin/env bash
set -euo pipefail

# Determine repo root safely (works in Actions and locally)
REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "${GITHUB_WORKSPACE:-$PWD}")"
: "${REPO:=$PWD}"

# Configure author LOCALLY for this repo (no --global)
git -C "$REPO" config --local user.email "actions@users.noreply.github.com"
git -C "$REPO" config --local user.name  "SBX Handover Bot"

# (Optional) silence any safe.directory warnings on GH-hosted runners
git config --global --add safe.directory "$REPO" || true

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
# Build workflow_url if running in Actions or if env vars available
WORKFLOW_URL=""
if [[ -n "${GITHUB_RUN_ID-}" && -n "${GITHUB_REPOSITORY-}" ]]; then
  GITHUB_SERVER_URL=${GITHUB_SERVER_URL:-https://github.com}
  WORKFLOW_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

# Determine generated_by: github-actions when running in GH Actions, otherwise local
if [[ "${GITHUB_ACTIONS-}" == "true" ]]; then
  GENERATED_BY="github-actions"
else
  GENERATED_BY="local"
fi

cat > "$STATUS_FILE" <<EOF
{
  "timestamp_utc": "$TIMESTAMP",
  "commit": "",
  "file": "$HANDOVER_FILE",
  "generated_by": "${GENERATED_BY}",
  "run_id": "${GITHUB_RUN_ID-}",
  "runner_hostname": "$(hostname 2>/dev/null || true)",
  "workflow_url": "${WORKFLOW_URL}"
}
EOF

git -C "$REPO" add "handover/SBX_Handover.md" "handover/status.json"
commit_msg="SBX handover sync — ${TIMESTAMP} UTC"
if git -C "$REPO" commit -m "$commit_msg"; then
  echo "[info] committed appended line"
else
  echo "[info] no changes to commit (nothing appended?)"
fi

# ---- Push with retries/backoff (POSIX-safe arithmetic) ----
: "${TARGET_BRANCH:=$BRANCH}"
: "${PUSH_RETRIES:=5}"
: "${PUSH_BACKOFF_BASE:=2}"

retries="$PUSH_RETRIES"
delay=1

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[info] dry-run mode enabled; skipping actual push"
else
  echo "[info] pushing to origin/$TARGET_BRANCH"
  if ! git -C "$REPO" push origin "$TARGET_BRANCH"; then
    while [ "$retries" -gt 0 ]; do
      echo "[warn] push failed; retrying in ${delay}s (retries left: $retries)"
      sleep "$delay"

      # Rebase to reduce chances of non-fast-forward, then try again
      if git -C "$REPO" pull --rebase origin "$TARGET_BRANCH" && git -C "$REPO" push origin "$TARGET_BRANCH"; then
        echo "[info] push succeeded after retry"
        break
      fi

      retries=$((retries-1))
      delay=$((delay * PUSH_BACKOFF_BASE))
    done

    if [ "$retries" -eq 0 ]; then
      echo "[error] push failed after ${PUSH_RETRIES} retries"
      exit 1
    fi
  fi
fi
# ---- end push with retries ----

echo "[info] done. appended: $LINE"
COMMIT_SHORT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true)
echo "[info] status: $STATUS_FILE (commit: ${COMMIT_SHORT:-})"
WORKFLOW_URL=""
if [[ -n "${GITHUB_RUN_ID-}" && -n "${GITHUB_REPOSITORY-}" ]]; then
  GITHUB_SERVER_URL=${GITHUB_SERVER_URL:-https://github.com}
  WORKFLOW_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

# Determine generated_by: github-actions when running in GH Actions, otherwise local
if [[ "${GITHUB_ACTIONS-}" == "true" ]]; then
  GENERATED_BY="github-actions"
else
  GENERATED_BY="local"
fi

cat > "$STATUS_FILE" <<EOF
{
  "timestamp_utc": "$TIMESTAMP",
  "commit": "",
  "file": "$HANDOVER_FILE",
  "generated_by": "${GENERATED_BY}",
  "run_id": "${GITHUB_RUN_ID-}",
  "runner_hostname": "$(hostname 2>/dev/null || true)",
  "workflow_url": "${WORKFLOW_URL}"
}
EOF

git -C "$REPO" add "handover/SBX_Handover.md" "handover/status.json"
commit_msg="SBX handover sync — ${TIMESTAMP} UTC"
if git -C "$REPO" commit -m "$commit_msg"; then
  echo "[info] committed appended line"
else
  echo "[info] no changes to commit (nothing appended?)"
fi

# ---- Push with retries/backoff (POSIX-safe arithmetic) ----
: "${TARGET_BRANCH:=$BRANCH}"
: "${PUSH_RETRIES:=5}"
: "${PUSH_BACKOFF_BASE:=2}"

retries="$PUSH_RETRIES"
delay=1

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[info] dry-run mode enabled; skipping actual push"
else
  echo "[info] pushing to origin/$TARGET_BRANCH"
  if ! git -C "$REPO" push origin "$TARGET_BRANCH"; then
    while [ "$retries" -gt 0 ]; do
      echo "[warn] push failed; retrying in ${delay}s (retries left: $retries)"
      sleep "$delay"

      # Rebase to reduce chances of non-fast-forward, then try again
      if git -C "$REPO" pull --rebase origin "$TARGET_BRANCH" && git -C "$REPO" push origin "$TARGET_BRANCH"; then
        echo "[info] push succeeded after retry"
        break
      fi

      retries=$((retries-1))
      delay=$((delay * PUSH_BACKOFF_BASE))
    done

    if [ "$retries" -eq 0 ]; then
      echo "[error] push failed after ${PUSH_RETRIES} retries"
      exit 1
    fi
  fi
fi
# ---- end push with retries ----

echo "[info] done. appended: $LINE"
COMMIT_SHORT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true)
echo "[info] status: $STATUS_FILE (commit: ${COMMIT_SHORT:-})"
#!/usr/bin/env bash
set -euo pipefail

# Determine repo root safely (works in Actions and locally)
REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo "${GITHUB_WORKSPACE:-$PWD}")"
: "${REPO:=$PWD}"     # final guard for set -u

# Configure author LOCALLY for this repo (no --global)
git -C "$REPO" config --local user.email "actions@users.noreply.github.com"
git -C "$REPO" config --local user.name  "SBX Handover Bot"

# (Optional) silence any safe.directory warnings on GH-hosted runners
git config --global --add safe.directory "$REPO" || true

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
# Build workflow_url if running in Actions or if env vars available
WORKFLOW_URL=""
if [[ -n "${GITHUB_RUN_ID-}" && -n "${GITHUB_REPOSITORY-}" ]]; then
  GITHUB_SERVER_URL=${GITHUB_SERVER_URL:-https://github.com}
  WORKFLOW_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

# Determine generated_by: github-actions when running in GH Actions, otherwise local
if [[ "${GITHUB_ACTIONS-}" == "true" ]]; then
  GENERATED_BY="github-actions"
else
  GENERATED_BY="local"
fi

cat > "$STATUS_FILE" <<EOF
{
  "timestamp_utc": "$TIMESTAMP",
  "commit": "",
  "file": "$HANDOVER_FILE",
  "generated_by": "${GENERATED_BY}",
  "run_id": "${GITHUB_RUN_ID-}",
  "runner_hostname": "$(hostname 2>/dev/null || true)",
  "workflow_url": "${WORKFLOW_URL}"
}
EOF

git -C "$REPO" add "handover/SBX_Handover.md" "handover/status.json"
commit_msg="SBX handover sync — ${TIMESTAMP} UTC"
if git -C "$REPO" commit -m "$commit_msg"; then
  echo "[info] committed appended line"
else
  echo "[info] no changes to commit (nothing appended?)"
fi

: "${TARGET_BRANCH:=$BRANCH}"
: "${PUSH_RETRIES:=5}"
: "${PUSH_BACKOFF_BASE:=2}"

retries="$PUSH_RETRIES"
delay=1

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[info] dry-run mode enabled; skipping actual push"
else
  echo "[info] pushing to origin/$TARGET_BRANCH"
  if ! git -C "$REPO" push origin "$TARGET_BRANCH"; then
    while [ "$retries" -gt 0 ]; do
      echo "[warn] push failed; retrying in ${delay}s (retries left: $retries)"
      sleep "$delay"

      # Rebase to reduce chances of non-fast-forward, then try again
      if git -C "$REPO" pull --rebase origin "$TARGET_BRANCH" && git -C "$REPO" push origin "$TARGET_BRANCH"; then
        echo "[info] push succeeded after retry"
        break
      fi

      retries=$((retries-1))
      delay=$((delay * PUSH_BACKOFF_BASE))
    done

    if [ "$retries" -eq 0 ]; then
      echo "[error] push failed after ${PUSH_RETRIES} retries"
      exit 1
    fi
  fi
fi

echo "[info] done. appended: $LINE"
COMMIT_SHORT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true)
echo "[info] status: $STATUS_FILE (commit: ${COMMIT_SHORT:-})"
        default: OPENAI_API_KEY

      thread_id_secret:
