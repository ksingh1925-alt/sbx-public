.PHONY: handover-sync handover-dry handover-pr check

handover-sync:
	@bash scripts/append_handover.sh

handover-dry:
	@bash scripts/append_handover.sh --dry-run

handover-pr:
	@bash scripts/append_handover.sh --branch handover-sync

check:
	@echo "Last 3 lines of handover/SBX_Handover.md:"
	@tail -n 3 handover/SBX_Handover.md || true
	@echo "\nhandover/status.json:"
	@cat handover/status.json || true
