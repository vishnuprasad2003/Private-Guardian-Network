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
        install-systemd enable-systemd disable-systemd \
        network-up network-down network-status network-logs \
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
	@echo "  Systemd (production):"
	@echo "    make install-systemd      Install units (user/path from whoami + CURDIR)"
	@echo "    make enable-systemd       Enable on boot"
	@echo "    make network-up           Start anvil + 3 guardians"
	@echo "    make network-down         Stop network"
	@echo "    make disable-systemd      Disable boot + stop (local teardown)"
	@echo "    make network-status       Status"
	@echo "    make network-logs         Follow journald"
	@echo ""
	@echo "  Maintenance:"
	@echo "    make status               Show versions & running processes"
	@echo "    make upgrade              Backup → pull → build → verify"
	@echo "    make upgrade-check        Check for updates"
	@echo "    make backup               Create a backup"
	@echo "    make clean                Remove data, logs, keys, pids"
	@echo "    make clean-foundry        Migrate ~/.foundry to /solana/wormhole/.foundry"
	@echo ""
	@echo "  WARNING: make deploy-anvil only on a fresh Anvil with no registry."
	@echo "  Never deploy-anvil on the VM if GETH_CONTRACT is already live in anvil-state.json."
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
	@echo "WARNING: only for empty Anvil. On the VM with an existing GETH_CONTRACT in anvil-state.json, skip this."
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

clean-foundry:
	@echo "Cleaning old ~/.foundry directory (migrates to /solana/wormhole/.foundry)..."
	@bash -c ' \
		if [[ -d "$$HOME/.foundry" && ! -L "$$HOME/.foundry" ]]; then \
			echo "Stopping Anvil if running..."; \
			./scripts/stop-anvil.sh 2>/dev/null || true; \
			sleep 2; \
			echo "Removing large anvil temp files..."; \
			rm -rf "$$HOME/.foundry/anvil" 2>/dev/null || true; \
			echo "Preserving bin/versions (if any)..."; \
			mkdir -p /solana/wormhole/.foundry/bin /solana/wormhole/.foundry/versions; \
			[[ -d "$$HOME/.foundry/bin" ]] && cp -r "$$HOME/.foundry/bin"/* /solana/wormhole/.foundry/bin/ 2>/dev/null || true; \
			[[ -d "$$HOME/.foundry/versions" ]] && cp -r "$$HOME/.foundry/versions"/* /solana/wormhole/.foundry/versions/ 2>/dev/null || true; \
			echo "Removing old ~/.foundry directory..."; \
			rm -rf "$$HOME/.foundry" 2>/dev/null || true; \
			echo "Creating symlink ~/.foundry → /solana/wormhole/.foundry"; \
			ln -sf /solana/wormhole/.foundry "$$HOME/.foundry"; \
			echo "Done. Space freed in home directory."; \
		elif [[ -L "$$HOME/.foundry" ]]; then \
			echo "~/.foundry is already a symlink: $$(readlink "$$HOME/.foundry")"; \
		else \
			echo "~/.foundry does not exist. Creating symlink..."; \
			mkdir -p /solana/wormhole/.foundry; \
			ln -sf /solana/wormhole/.foundry "$$HOME/.foundry"; \
			echo "Done."; \
		fi'

# Substituted into systemd unit templates at install time. Override on the
# Azure host if needed: make install-systemd GUARDIAN_USER=azureuser WORKSPACE_ROOT=/home/azureuser/Private-Guardian-Network
GUARDIAN_USER  ?= $(shell whoami)
GUARDIAN_GROUP ?= $(shell id -gn)
WORKSPACE_ROOT ?= $(CURDIR)
HOME_DIR       ?= $(shell getent passwd $(GUARDIAN_USER) | cut -d: -f6)

install-systemd:
	@echo "Installing systemd services for user=$(GUARDIAN_USER) workspace=$(WORKSPACE_ROOT)..."
	@chmod +x scripts/*.sh scripts/*.py 2>/dev/null || true
	@tmpdir=$$(mktemp -d) && \
	 GUARDIAN_USER='$(GUARDIAN_USER)' GUARDIAN_GROUP='$(GUARDIAN_GROUP)' \
	 WORKSPACE_ROOT='$(WORKSPACE_ROOT)' HOME_DIR='$(HOME_DIR)' \
	 python3 scripts/render-systemd-units.py "$$tmpdir" && \
	 sudo cp "$$tmpdir/anvil.service" /etc/systemd/system/ && \
	 sudo cp "$$tmpdir/guardian@.service" /etc/systemd/system/ && \
	 sudo cp systemd/guardian.target /etc/systemd/system/ && \
	 sudo cp systemd/logrotate.conf /etc/logrotate.d/wormhole-guardian && \
	 rm -rf "$$tmpdir" && \
	 sudo systemctl daemon-reload && \
	 echo "Done. Next: 'make enable-systemd' then 'make network-up' (skip deploy-anvil if registry already exists)."

# Enable the whole network to start on boot (anvil + 3 guardians via the target).
enable-systemd:
	@sudo systemctl enable anvil.service \
	    guardian@guardian-0.service guardian@guardian-1.service guardian@guardian-2.service \
	    guardian.target && \
	 echo "Enabled. The guardian network now starts on boot and auto-restarts on failure."

# Stop + disable boot (local teardown). Does not wipe BASE_DIR/data.
disable-systemd:
	@sudo systemctl stop guardian.target anvil.service
	@sudo systemctl disable guardian.target anvil.service \
	    guardian@guardian-0.service guardian@guardian-1.service guardian@guardian-2.service
	@sudo systemctl reset-failed anvil.service \
	    guardian@guardian-0.service guardian@guardian-1.service guardian@guardian-2.service 2>/dev/null || true
	@echo "Stopped and disabled. Runtime data under /solana/wormhole was not deleted."

# Start / stop / inspect the whole network through systemd (auto-restart active).
network-up:
	@sudo systemctl start guardian.target && echo "guardian.target started."

network-down:
	@sudo systemctl stop guardian.target && echo "guardian.target stopped."

network-status:
	@systemctl --no-pager status anvil.service \
	    guardian@guardian-0.service guardian@guardian-1.service guardian@guardian-2.service || true

network-logs:
	@sudo journalctl -f -u anvil.service \
	    -u guardian@guardian-0.service -u guardian@guardian-1.service -u guardian@guardian-2.service
