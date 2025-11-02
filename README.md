# SBX public handover mirror

Public handover mirror; timestamped sync line in `handover/SBX_Handover.md`.

Quick-start

- Codespaces: open this repository in a Codespace. The included task (Cmd/Ctrl+Shift+B) runs the append script.
- VS Code local: open the repo, run the task `Append SBX handover timestamp` from the Run Tasks UI or use the Makefile target.

One-line append command example

```bash
echo "SBX handover sync — $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> handover/SBX_Handover.md
```

Files of interest

- `scripts/append_handover.sh` — appends a UTC timestamp, commits, and pushes to `origin/main`.
- `.vscode/tasks.json` — VS Code task to run the script (Cmd/Ctrl+Shift+B).
- `Makefile` — contains `handover-sync` and `check` targets.

Notes

- The workflow `.github/workflows/handover_sync.yml` (optional) can be run manually via GitHub's Actions UI to perform the same operation in CI.
- The script will append one UTC line per run; avoid running concurrently to prevent race conditions.
