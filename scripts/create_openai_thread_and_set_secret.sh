#!/usr/bin/env bash
set -euo pipefail

# Create an OpenAI thread and set the returned thread id as the
# OPENAI_THREAD_ID secret in the current GitHub repository using the gh CLI.
# Requirements:
# - OPENAI_API_KEY set in the environment
# - gh (GitHub CLI) installed and authenticated
# - curl and either jq or python3 available

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "ERROR: OPENAI_API_KEY is not set. Export your key first: export OPENAI_API_KEY=sk-..."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required. Install it and retry." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is required to set the repo secret. Install and authenticate (gh auth login)." >&2
  exit 1
fi

echo "Creating OpenAI thread..."
resp=$(curl -sS -X POST "https://api.openai.com/v1/threads" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{}')

echo "API response:" >&2
echo "$resp" | sed 's/^/  /' >&2

# Extract thread id
thread_id=""
if command -v jq >/dev/null 2>&1; then
  thread_id=$(echo "$resp" | jq -r '.id // .thread.id // .thread_id // empty')
else
  thread_id=$(python3 - <<PY
import sys, json
try:
    j = json.load(sys.stdin)
except Exception:
    print('', end='')
    sys.exit(0)
tid = j.get('id') or (j.get('thread') or {}).get('id') or j.get('thread_id') or ''
print(tid)
PY
  <<<"$resp")
fi

if [ -z "${thread_id}" ]; then
  echo "ERROR: could not extract thread id from API response. Inspect output above." >&2
  exit 2
fi

echo "Thread ID: $thread_id"

# Determine target repo for gh (current repo if possible)
REPO=""
if command -v gh >/dev/null 2>&1; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi
if [ -z "$REPO" ]; then
  # try git remote
  ORIGIN_URL=$(git config --get remote.origin.url || true)
  if [ -n "$ORIGIN_URL" ]; then
    # try to extract owner/repo
    REPO=$(echo "$ORIGIN_URL" | sed -n 's#.*[:/]\([^/:][^/:]*/[^/:][^/:]*\)\(.git\)*$#\1#p')
  fi
fi

if [ -z "$REPO" ]; then
  echo "ERROR: couldn't determine repository. Set OPENAI_THREAD_ID manually in your repo settings or pass --repo to gh." >&2
  exit 3
fi

echo "Setting GitHub secret OPENAI_THREAD_ID in repo: $REPO"
echo -n "$thread_id" | gh secret set OPENAI_THREAD_ID --repo "$REPO"

echo "Done. COPY THIS VALUE into any other systems that need it (or use the secret in Actions)."
echo "$thread_id"
./scripts/append_handover.sh --dry-run

./scripts/append_handover.sh --dry-run

