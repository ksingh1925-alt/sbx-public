.PHONY: handover-sync check

handover-sync:
	@bash scripts/append_handover.sh

check:
	@echo "Last 3 lines of handover/SBX_Handover.md:"
	@tail -n 3 handover/SBX_Handover.md || true
