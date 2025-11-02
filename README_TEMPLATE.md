# SBX public handover mirror (template)

Public handover mirror; this repo stores timestamped handover sync lines in `handover/SBX_Handover.md` and a machine-readable `handover/status.json`.

Quick start

- Clone this repo and run `scripts/setup_handover.sh` to initialize handover files.
- Use `scripts/append_handover.sh` to append a UTC timestamp, commit, and push.

Files

- `scripts/append_handover.sh` — appends timestamp and writes `status.json`.
- `scripts/dispatch_workflow.sh` — dispatch the GitHub Actions workflow via `gh` CLI.
