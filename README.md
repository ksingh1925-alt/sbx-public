# SBX public handover mirror

[![SBX Handover Sync](https://github.com/ksingh1925-alt/sbx-public/actions/workflows/handover_sync.yml/badge.svg?branch=main)](https://github.com/ksingh1925-alt/sbx-public/actions/workflows/handover_sync.yml)

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
- The script will append one UTC line per run; use the included flock-based locking to avoid concurrency issues.

Public Endpoints

- SBX handover markdown (raw): https://raw.githubusercontent.com/ksingh1925-alt/sbx-public/main/handover/SBX_Handover.md
- status.json (raw): https://raw.githubusercontent.com/ksingh1925-alt/sbx-public/main/handover/status.json

How to trigger

- VS Code Task: Run the build task (Cmd/Ctrl+Shift+B) and select "Append SBX handover timestamp" or the dry-run / PR-mode tasks.
- Makefile: run `make handover-sync` (or `make handover-dry`, `make handover-pr`).
- GitHub Actions: Actions tab -> "SBX Handover Sync" -> Run workflow. Use the `use_pr_mode` input to push to a PR branch instead of main.

How to run

- VS Code Task: Run the build task (Cmd/Ctrl+Shift+B) and select "Append SBX handover timestamp" or choose the dry-run / PR-mode tasks.
- Makefile:
	- `make handover-sync` — append and push to main
	- `make handover-dry`  — run a dry-run (no commit/push)
	- `make handover-pr`   — create/commit on `handover-sync` branch and push
- GitHub Action: Actions tab -> "SBX Handover Sync" -> Run workflow (or it runs hourly via cron)

Notes about modes

- Dry-run: `--dry-run` prints actions without committing or pushing. Useful for testing.
- PR mode: `--branch <name>` creates/checks out the branch and pushes there (e.g. `--branch handover-sync`). Useful if you want a branch/PR workflow instead of pushing to `main`.
- Locking: the script uses `/tmp/sbx_handover.lock` via `flock` to prevent concurrent runs.

Reliability

- Workflow concurrency: the GitHub Action uses a `concurrency` group (`sbx-handover-sync`) so multiple workflow runs won't race.
- Push retries: the Action uses an exponential backoff retry loop when pushing (up to 5 attempts).
- Script lock: the script uses `flock` on `/tmp/sbx_handover.lock` to avoid local concurrent runs.
