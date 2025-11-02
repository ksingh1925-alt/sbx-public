# Replace <thread-id> with the value the script printed, or pipe it in.
echo "THE_THREAD_ID" | gh secret set OPENAI_THREAD_ID# Replace <thread-id> with the value the script printed, or pipe it in.
echo "THE_THREAD_ID" | gh secret set OPENAI_THREAD_ID#!/usr/bin/env bash
set -euo pipefail

# Dispatch the SBX Handover Sync workflow via GitHub CLI
# Usage: scripts/dispatch_workflow.sh [--ref <branch>]
REF="main"
if [[ ${1-} == "--ref" && -n ${2-} ]]; then
  REF="$2"
fi

echo "Dispatching workflow 'SBX Handover Sync' on ref: $REF (use_pr_mode=false)"
gh workflow run handover_sync.yml --ref "$REF" -f use_pr_mode=false
echo "Dispatched. Use 'gh run watch' to follow the run."
