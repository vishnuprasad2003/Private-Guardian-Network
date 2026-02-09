# ─────────────────────────────────────────────────────────────────────────────
# Private Guardian Network — Makefile
# ─────────────────────────────────────────────────────────────────────────────
.PHONY: help install-deps init \
        start-anvil stop-anvil \
        deploy-anvil deploy-avalanche deploy-solana deploy-solana-status \
        start-0 start-1 start-2 start-all \
        stop-0 stop-1 stop-2 stop-all \
        logs logs-0 logs-1 logs-2 logs-anvil \
        status clean \
        upgrade upgrade-check upgrade-status backup

# Default
help:
	@echo ""
	@echo "  Private Guardian Network"
	@echo "  ════════════════════════════════════════════════════"
	@echo ""
	@echo "  Setup:"
	@echo "    make install-deps         Install all dependencies (Foundry, wasmvm, grpcurl, Solana CLI)"
	@echo "    make init                 Create storage directories in BASE_DIR (/solana/wormhole)"
	@echo ""
	@echo "  Anvil (local EVM):"
	@echo "    make start-anvil          Start Anvil"
	@echo "    make stop-anvil           Stop Anvil"
	@echo ""
	@echo "  Deploy Contracts:"
	@echo "    make deploy-anvil         Deploy Wormhole to Anvil"
	@echo "    make deploy-avalanche     Deploy Wormhole to Avalanche"
	@echo "    make deploy-solana        Deploy & init Wormhole on Solana"
	@echo ""
	@echo "  Guardians:"
	@echo "    make start-0              Start guardian-0 (set hostname first)"
	@echo "    make start-1              Start guardian-1"
	@echo "    make start-2              Start guardian-2"
	@echo "    make start-all            Start all guardians sequentially"
	@echo "    make stop-0 / stop-1 / stop-2"
	@echo "    make stop-all             Stop everything (guardians + Anvil)"
	@echo ""
	@echo "  Logs:"
	@echo "    make logs                 Tail all guardian logs"
	@echo "    make logs-0 / logs-1 / logs-2 / logs-anvil"
	@echo ""
	@echo "  Maintenance:"
	@echo "    make status               Show versions & running processes"
	@echo "    make upgrade              Backup → pull → build → verify"
	@echo "    make upgrade-check        Check for updates"
	@echo "    make backup               Create a backup"
	@echo "    make clean                Remove data, logs, keys, pids"
	@echo ""

# ─── Setup ──────────────────────────────────────────────────────────────────

install-deps:
	@./scripts/install-deps.sh all

init:
	@bash -c 'source scripts/common.sh && \
		load_config configs/guardian-0.conf && \
		ensure_dirs && \
		log_success "Directories created in $${BASE_DIR}"'

# ─── Anvil ──────────────────────────────────────────────────────────────────

start-anvil:
	@./scripts/start-anvil.sh

stop-anvil:
	@./scripts/stop-anvil.sh

# ─── Deployment ─────────────────────────────────────────────────────────────

deploy-anvil:
	@./scripts/deploy-evm.sh anvil

deploy-avalanche:
	@./scripts/deploy-evm.sh avalanche

deploy-solana:
	@./scripts/deploy-solana.sh all

deploy-solana-status:
	@./scripts/deploy-solana.sh status

# ─── Start Guardians ────────────────────────────────────────────────────────

start-0:
	@./scripts/start-guardian.sh configs/guardian-0.conf

start-1:
	@./scripts/start-guardian.sh configs/guardian-1.conf

start-2:
	@./scripts/start-guardian.sh configs/guardian-2.conf

start-all: start-0
	@sleep 5
	@$(MAKE) start-1
	@sleep 3
	@$(MAKE) start-2

# ─── Stop Guardians ─────────────────────────────────────────────────────────

stop-0:
	@./scripts/stop-guardian.sh configs/guardian-0.conf

stop-1:
	@./scripts/stop-guardian.sh configs/guardian-1.conf

stop-2:
	@./scripts/stop-guardian.sh configs/guardian-2.conf

stop-all: stop-0 stop-1 stop-2 stop-anvil

# ─── Logs ───────────────────────────────────────────────────────────────────

logs:
	@echo "=== guardian-0 ===" && tail -30 /solana/wormhole/logs/guardian-0.log 2>/dev/null || true
	@echo ""
	@echo "=== guardian-1 ===" && tail -30 /solana/wormhole/logs/guardian-1.log 2>/dev/null || true
	@echo ""
	@echo "=== guardian-2 ===" && tail -30 /solana/wormhole/logs/guardian-2.log 2>/dev/null || true

logs-0:
	@tail -f /solana/wormhole/logs/guardian-0.log

logs-1:
	@tail -f /solana/wormhole/logs/guardian-1.log

logs-2:
	@tail -f /solana/wormhole/logs/guardian-2.log

logs-anvil:
	@tail -f /solana/wormhole/logs/anvil.log

# ─── Maintenance ────────────────────────────────────────────────────────────

status:
	@./scripts/upgrade.sh status

upgrade:
	@./scripts/upgrade.sh all

upgrade-check:
	@./scripts/upgrade.sh check

upgrade-status:
	@./scripts/upgrade.sh status

backup:
	@./scripts/upgrade.sh backup

clean:
	@echo "Cleaning /solana/wormhole data, logs, keys, pids, sockets..."
	@sudo rm -rf /solana/wormhole/data/* 2>/dev/null || rm -rf /solana/wormhole/data/* 2>/dev/null || true
	@rm -rf /solana/wormhole/logs/* /solana/wormhole/keys/* \
	        /solana/wormhole/pids/* /solana/wormhole/sockets/* 2>/dev/null || true
	@echo "Done"
