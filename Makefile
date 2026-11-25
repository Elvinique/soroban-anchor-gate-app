# SorobanAnchor Gate Monorepo Makefile

.PHONY: all install dev build build-contracts optimize-contracts verify-wasm-size wasm-checksum verify-wasm-reproducible verify-contracts-wasm build-client build-web build-relay test test-contracts test-client test-web test-relay lint clean help

WASM_DIR := contracts/target/wasm32-unknown-unknown/release
CONTRACT_WASM := $(WASM_DIR)/soroban_anchor_escrow.wasm
CONTRACT_OPTIMIZED_WASM := $(WASM_DIR)/soroban_anchor_escrow.optimized.wasm
WASM_CHECKSUM_FILE := $(WASM_DIR)/SHA256SUMS.txt
WASM_MAX_BYTES ?= 65536

all: build

# Install dependencies across all packages and services
install:
	./install.sh

# Start web frontend and Go relay daemon concurrently
dev:
	npm run dev

# Build all components
build: build-contracts build-client build-web build-relay

build-contracts:
	cd contracts && $(MAKE) build

# Build and optimize contract WASM with Soroban/Stellar CLI
optimize-contracts:
	@set -e; \
	rm -f "$(CONTRACT_OPTIMIZED_WASM)"; \
	(cd contracts && CARGO_INCREMENTAL=0 RUSTFLAGS="--remap-path-prefix=$$(pwd)=/workspace" cargo build --locked --target wasm32-unknown-unknown --release); \
	CLI=$$(command -v soroban || command -v stellar || true); \
	if [ -z "$$CLI" ]; then \
		echo "Error: neither 'soroban' nor 'stellar' CLI found. Install with: cargo install --locked stellar-cli" >&2; \
		exit 1; \
	fi; \
	(cd contracts && "$$CLI" contract optimize --wasm target/wasm32-unknown-unknown/release/soroban_anchor_escrow.wasm)

# Assert optimized WASM binary is non-empty and strictly under 64KB
verify-wasm-size:
	@set -e; \
	if ! printf '%s' "$(WASM_MAX_BYTES)" | grep -Eq '^[1-9][0-9]*$$'; then \
		echo "Error: WASM_MAX_BYTES must be a positive integer (got '$(WASM_MAX_BYTES)')" >&2; \
		exit 1; \
	fi; \
	if [ ! -f "$(CONTRACT_OPTIMIZED_WASM)" ]; then \
		echo "Error: optimized WASM not found at $(CONTRACT_OPTIMIZED_WASM). Run 'make optimize-contracts' first." >&2; \
		exit 1; \
	fi; \
	OPT_SIZE=$$(wc -c < "$(CONTRACT_OPTIMIZED_WASM)" | tr -d '[:space:]'); \
	if [ "$$OPT_SIZE" -le 0 ]; then \
		echo "Error: optimized WASM is empty (0 bytes): $(CONTRACT_OPTIMIZED_WASM)" >&2; \
		exit 1; \
	fi; \
	if [ "$$OPT_SIZE" -ge "$(WASM_MAX_BYTES)" ]; then \
		echo "Error: optimized WASM size ($${OPT_SIZE} bytes) meets or exceeds limit (< $(WASM_MAX_BYTES) bytes)." >&2; \
		exit 1; \
	fi; \
	echo "WASM size verification passed: $${OPT_SIZE} bytes (< $(WASM_MAX_BYTES) bytes limit)"

# Compute and verify SHA-256 checksums for release and optimized WASM binaries
wasm-checksum:
	@set -e; \
	if [ ! -f "$(CONTRACT_WASM)" ] || [ ! -f "$(CONTRACT_OPTIMIZED_WASM)" ]; then \
		echo "Error: WASM artifacts missing in $(WASM_DIR). Run 'make optimize-contracts' first." >&2; \
		exit 1; \
	fi; \
	if command -v sha256sum >/dev/null 2>&1; then \
		HASH_TOOL="sha256sum"; \
	elif command -v shasum >/dev/null 2>&1; then \
		HASH_TOOL="shasum -a 256"; \
	else \
		echo "Error: neither 'sha256sum' nor 'shasum' is available." >&2; \
		exit 1; \
	fi; \
	(cd "$(WASM_DIR)" && $$HASH_TOOL soroban_anchor_escrow.wasm soroban_anchor_escrow.optimized.wasm > SHA256SUMS.txt && $$HASH_TOOL -c SHA256SUMS.txt); \
	echo "Checksums written to $(WASM_CHECKSUM_FILE):"; \
	cat "$(WASM_CHECKSUM_FILE)"

# Verify deterministic WASM output across two clean contract builds
verify-wasm-reproducible:
	@set -e; \
	if command -v sha256sum >/dev/null 2>&1; then \
		HASH_TOOL="sha256sum"; \
	elif command -v shasum >/dev/null 2>&1; then \
		HASH_TOOL="shasum -a 256"; \
	else \
		echo "Error: neither 'sha256sum' nor 'shasum' is available." >&2; \
		exit 1; \
	fi; \
	$(MAKE) optimize-contracts; \
	if [ ! -f "$(CONTRACT_OPTIMIZED_WASM)" ]; then \
		echo "Error: optimized WASM missing after build 1." >&2; \
		exit 1; \
	fi; \
	HASH_1=$$($$HASH_TOOL "$(CONTRACT_OPTIMIZED_WASM)" | awk '{print $$1}'); \
	if [ -z "$$HASH_1" ]; then \
		echo "Error: failed to compute SHA-256 hash for build 1." >&2; \
		exit 1; \
	fi; \
	(cd contracts && cargo clean -p soroban-anchor-escrow); \
	$(MAKE) optimize-contracts; \
	if [ ! -f "$(CONTRACT_OPTIMIZED_WASM)" ]; then \
		echo "Error: optimized WASM missing after build 2." >&2; \
		exit 1; \
	fi; \
	HASH_2=$$($$HASH_TOOL "$(CONTRACT_OPTIMIZED_WASM)" | awk '{print $$1}'); \
	if [ -z "$$HASH_2" ]; then \
		echo "Error: failed to compute SHA-256 hash for build 2." >&2; \
		exit 1; \
	fi; \
	if [ "$$HASH_1" != "$$HASH_2" ]; then \
		echo "Error: non-reproducible optimized WASM build!" >&2; \
		echo "  Build 1 SHA-256: $$HASH_1" >&2; \
		echo "  Build 2 SHA-256: $$HASH_2" >&2; \
		exit 1; \
	fi; \
	echo "Reproducible build verified: $$HASH_1"

# Run full WASM optimization, reproducibility, size limit, and checksum pipeline
verify-contracts-wasm: verify-wasm-reproducible verify-wasm-size wasm-checksum

build-client:
	cd packages/contract-client && npm run build

build-web:
	cd apps/web && npm run build

build-relay:
	cd services/relay && go build -o relay cmd/relay/main.go

# Run all test suites
test: test-contracts test-client test-web test-relay

test-contracts:
	cd contracts && cargo test

test-client:
	cd packages/contract-client && npm test

test-web:
	cd apps/web && npm test

test-relay:
	cd services/relay && go test -v -race ./...

# Run formatters and linters
lint:
	cd contracts && cargo fmt --check
	cd packages/contract-client && npm run typecheck
	cd apps/web && npm run lint && npm run typecheck
	cd services/relay && go vet ./...

# Clean build artifacts
clean:
	npm run clean

help:
	@echo "Available commands:"
	@echo "  make install                  - Run install.sh and install all dependencies"
	@echo "  make dev                      - Start Next.js web interface and Go relay"
	@echo "  make build                    - Build contracts WASM, SDK, web, and relay"
	@echo "  make optimize-contracts       - Build and optimize contract WASM via Soroban/Stellar CLI"
	@echo "  make verify-wasm-size         - Assert optimized contract WASM is under 64KB"
	@echo "  make wasm-checksum            - Generate and verify SHA-256 checksums for WASM builds"
	@echo "  make verify-wasm-reproducible - Verify deterministic WASM output across clean builds"
	@echo "  make verify-contracts-wasm    - Run full WASM optimization, size, hash, and reproducibility checks"
	@echo "  make test                     - Run all automated test suites"
	@echo "  make test-contracts           - Run Soroban smart contract tests"
	@echo "  make test-web                 - Run Next.js web application tests"
	@echo "  make test-relay               - Run Go relay service race tests"
	@echo "  make test-client              - Run TypeScript contract client tests"
	@echo "  make lint                     - Run linters across all codebases"
	@echo "  make clean                    - Remove build artifacts and node_modules"
