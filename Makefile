.PHONY: help install start-anvil stop-anvil deploy-anvil deploy-avalanche deploy-solana start stop logs clean upgrade upgrade-check upgrade-status

help:
	@echo "Private Guardian Network"
	@echo ""
	@echo "Setup:"
	@echo "  make install            Install dependencies (Foundry, grpcurl)"
	@echo ""
	@echo "Services:"
	@echo "  make start-anvil        Start Anvil (guardian registry)"
	@echo "  make stop-anvil         Stop Anvil"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-anvil       Deploy Wormhole to Anvil"
	@echo "  make deploy-avalanche   Deploy Wormhole to Avalanche"
	@echo "  make deploy-solana      Deploy Wormhole to Solana"
	@echo "  make deploy-solana-status  Check Solana deployment status"
	@echo ""
	@echo "Guardian Nodes:"
	@echo "  make start-0            Start guardian-0 (sudo hostname guardian-0 first)"
	@echo "  make start-1            Start guardian-1 (sudo hostname guardian-1 first)"
	@echo "  make start-2            Start guardian-2 (sudo hostname guardian-2 first)"
	@echo "  make stop               Stop all guardians"
	@echo "  make logs               Show guardian logs"
	@echo ""
	@echo "Upgrade & Maintenance:"
	@echo "  make upgrade            Full upgrade (backup + update + verify)"
	@echo "  make upgrade-check      Check for available updates"
	@echo "  make upgrade-status     Show current version and status"
	@echo "  make backup             Create backup before manual changes"
	@echo ""
	@echo "Utilities:"
	@echo "  make clean              Clean data, logs, keys"

install:
	@echo "Installing Foundry..."
	@curl -L https://foundry.paradigm.xyz | bash
	@~/.foundry/bin/foundryup
	@echo "Installing grpcurl..."
	@go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
	@echo "Installing Solana CLI..."
	@sh -c "$$(curl -sSfL https://release.solana.com/stable/install)"
	@echo "Done. Add to PATH: export PATH=\"$$HOME/go/bin:$$HOME/.foundry/bin:$$HOME/.local/share/solana/install/active_release/bin:$$PATH\""

start-anvil:
	@./scripts/start-anvil.sh

stop-anvil:
	@./scripts/stop-anvil.sh

deploy-anvil:
	@./scripts/deploy-evm.sh anvil

deploy-avalanche:
	@./scripts/deploy-evm.sh avalanche

deploy-solana:
	@./scripts/deploy-solana.sh all

deploy-solana-status:
	@./scripts/deploy-solana.sh status

start-0:
	@./scripts/start-guardian.sh configs/guardian-0.conf

start-1:
	@./scripts/start-guardian.sh configs/guardian-1.conf

start-2:
	@./scripts/start-guardian.sh configs/guardian-2.conf

stop:
	@pkill -f guardiand 2>/dev/null || true
	@rm -f /solana/wormhole/*.pid /solana/wormhole/anvil.pid 2>/dev/null || true
	@echo "Stopped all guardians"

logs:
	@echo "=== Guardian-0 ===" && tail -20 /solana/wormhole/logs/guardian-0.log 2>/dev/null || echo "No logs"
	@echo ""
	@echo "=== Guardian-1 ===" && tail -20 /solana/wormhole/logs/guardian-1.log 2>/dev/null || echo "No logs"
	@echo ""
	@echo "=== Guardian-2 ===" && tail -20 /solana/wormhole/logs/guardian-2.log 2>/dev/null || echo "No logs"

clean:
	@sudo rm -rf /solana/wormhole/data/* 2>/dev/null || rm -rf /solana/wormhole/data/* 2>/dev/null || true
	@rm -rf /solana/wormhole/logs/* /solana/wormhole/keys/* /solana/wormhole/*.pid 2>/dev/null || true
	@echo "Cleaned data, logs, keys, and pid files from /solana/wormhole"

# ─────────────────────────────────────────────────────────────────────────────
# Upgrade & Maintenance
# ─────────────────────────────────────────────────────────────────────────────

upgrade:
	@./scripts/upgrade.sh all

upgrade-check:
	@./scripts/upgrade.sh check

upgrade-status:
	@./scripts/upgrade.sh status

backup:
	@./scripts/upgrade.sh backup

rollback:
	@./scripts/upgrade.sh list-backups
	@echo ""
	@echo "Usage: ./scripts/upgrade.sh rollback backups/<timestamp>"
