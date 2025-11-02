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

echo "[info] pushing to origin/$BRANCH"
git -C "$REPO" push origin "$BRANCH"

echo "[info] done. appended: $LINE"
COMMIT_SHORT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || true)
echo "[info] status: $STATUS_FILE (commit: ${COMMIT_SHORT:-})"

- name: Upload status.json artifact
  uses: actions/upload-artifact@v4
  with:
    name: handover-status
    path: |
      handover/status.json
      handover/SBX_Handover.md

if [[ $DRY_RUN -eq 1 ]]; then
  echo "[info] dry-run mode enabled; skipping actual push"
finame: Post to OpenAI Thread

on:
  workflow_dispatch:
    inputs:
      artifact_name:
        description: Artifact to fetch (default: handover-status)
        default: handover-status
      dry_run:
        description: Print payload only (no POST)
        default: "true"
      retry_max:
        description: Max retries for POST
        default: "5"
      backoff_base:
        description: Base seconds for exponential backoff
        default: "2"
      api_key_secret:
        description: Secret name for API key
        default: OPENAI_API_KEY
      thread_id_secret:
        description: Secret name for thread id
        default: OPENAI_THREAD_ID

jobs:
  post:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download handover artifact
        uses: actions/download-artifact@v4
        with:
          name: ${{ inputs.artifact_name }}
          path: handover

      - name: Build message text
        id: build
        shell: bash
        run: |
          set -euo pipefail
          TS=$(jq -r '.timestamp_utc // empty' handover/status.json)
          RUN_URL=$(jq -r '.workflow_url // empty' handover/status.json)
          HOST=$(jq -r '.runner_hostname // empty' handover/status.json)
          LAST_LINE=$(tail -n 1 handover/SBX_Handover.md || true)

          {
            echo "SBX handover sync — ${TS}"
            [ -n "$LAST_LINE" ] && echo "$LAST_LINE"
            [ -n "$RUN_URL" ] && echo "run: ${RUN_URL}"
            [ -n "$HOST" ] && echo "host: ${HOST}"
          } > message.txt

          echo "payload_path=message.txt" >> "$GITHUB_OUTPUT"

      - name: Dry run (print payload only)
        if: ${{ inputs.dry_run == 'true' }}
        shell: bash
        run: |
          echo "---- DRY RUN PAYLOAD ----"
          cat message.txt
          echo "-------------------------"

      - name: Post message to OpenAI thread (with retries)
        if: ${{ inputs.dry_run != 'true' }}
        env:
          OPENAI_API_KEY: ${{ secrets[inputs.api_key_secret] }}
          THREAD_ID: ${{ secrets[inputs.thread_id_secret] }}
          RETRY_MAX: ${{ inputs.retry_max }}
          BACKOFF_BASE: ${{ inputs.backoff_base }}
        shell: bash
        run: |
          set -euo pipefail

          if [ -z "${OPENAI_API_KEY:-}" ] || [ -z "${THREAD_ID:-}" ]; then
            echo "Missing OPENAI_API_KEY or THREAD_ID secret"; exit 1
          fi

          # Escape payload for JSON
          ESCAPED=$(python3 - <<'PY'
import json, sys
print(json.dumps(open("message.txt","r",encoding="utf-8").read()))
PY
)

          try_post() {
            # assistants v2 requires the beta header, we post a message to the thread
            curl -sS -w '\nHTTP:%{http_code}\n' \
              -X POST "https://api.openai.com/v1/threads/${THREAD_ID}/messages" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${OPENAI_API_KEY}" \
              -H "OpenAI-Beta: assistants=v2" \
              -d "{\"role\":\"user\",\"content\":${ESCAPED}}" 
          }

          max="${RETRY_MAX:-5}"
          base="${BACKOFF_BASE:-2}"

          i=1
          while [ "$i" -le "$max" ]; do
            RESP=$(try_post)
            CODE=$(printf "%s" "$RESP" | tail -n1 | sed 's/^HTTP://')
            BODY=$(printf "%s" "$RESP" | sed '$d')

            echo "Attempt $i/$max → HTTP ${CODE}"
            if echo "$CODE" | grep -qE '^(200|201|202|204)$'; then
              echo "Success"; echo "$BODY"; exit 0
            fi

            if [ "$i" -lt "$max" ]; then
              # cap backoff to something reasonable
              SLEEP=$(( base ** i ))
              [ "$SLEEP" -gt 30 ] && SLEEP=30
              echo "Retrying in ${SLEEP}s…"
              sleep "$SLEEP"
            fi
            i=$((i+1))
          done

          echo "Failed after ${max} attempts"
          exit 1

