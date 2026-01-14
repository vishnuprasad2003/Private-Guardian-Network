.PHONY: help install start-anvil stop-anvil deploy-anvil deploy-avalanche deploy-solana start stop logs clean

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
	@echo "  make stop               Stop all guardians"
	@echo "  make logs               Show guardian logs"
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

stop:
	@pkill -f guardiand 2>/dev/null || true
	@rm -f *.pid
	@echo "Stopped all guardians"

logs:
	@echo "=== Guardian-0 ===" && tail -20 logs/guardian-0.log 2>/dev/null || echo "No logs"
	@echo ""
	@echo "=== Guardian-1 ===" && tail -20 logs/guardian-1.log 2>/dev/null || echo "No logs"

clean:
	@sudo rm -rf data/* 2>/dev/null || rm -rf data/* 2>/dev/null || true
	@rm -rf logs/* keys/* *.pid 2>/dev/null || true
	@echo "Cleaned data, logs, keys, and pid files"
