#!/usr/bin/env bash
#
# Bootstrap entrypoint for the Soroban Anchor Gate sandbox.
# Waits for the Soroban RPC to become healthy, optionally deploys the escrow
# contract WASM via soroban-cli, and writes the resulting contract ID to .env.
set -euo pipefail

RPC_URL="${SOROBAN_RPC_URL:-http://soroban-rpc:8000}"
NETWORK_PASSPHRASE="${NETWORK_PASSPHRASE:-Test SDF Network ; September 2015}"
CONTRACT_WASM="${CONTRACT_WASM:-/contract.wasm}"
ENV_FILE="${ENV_FILE:-/app/.env}"
DEFAULT_CONTRACT_ID="CBIHLECKLMXYK6FPHSGGVYF6AHNFRHR3T5EIFIS3PFQDFKDQWNR25PHT"

log() {
  printf '[init] %s\n' "$*"
}

log "Waiting for Soroban RPC at ${RPC_URL} ..."
rpc_ready=0
for i in $(seq 1 60); do
  if curl -sf "${RPC_URL}" >/dev/null 2>&1; then
    rpc_ready=1
    break
  fi
  sleep 2
done

if [ "${rpc_ready}" -ne 1 ]; then
  log "Soroban RPC not reachable; falling back to default contract ID: ${DEFAULT_CONTRACT_ID}" >&2
fi

CONTRACT_ID="${DEFAULT_CONTRACT_ID}"

if [ -n "${DEPLOYMENT_KEY_SECRET:-}" ] && [ -f "${CONTRACT_WASM}" ]; then
  log "Deploying contract WASM via soroban-cli ..."
  if DEPLOYED_ID="$(soroban contract deploy \
    --rpc-url "${RPC_URL}" \
    --network-passphrase "${NETWORK_PASSPHRASE}" \
    --source-key "${DEPLOYMENT_KEY_SECRET}" \
    --wasm "${CONTRACT_WASM}" 2>/dev/null)"; then
    CONTRACT_ID="${DEPLOYED_ID}"
    log "Contract deployed with ID: ${CONTRACT_ID}"
  else
    log "Contract deployment failed; falling back to default contract ID: ${CONTRACT_ID}" >&2
  fi
elif [ -n "${DEPLOYMENT_KEY_SECRET:-}" ]; then
  log "Deployment key provided but contract WASM not found at ${CONTRACT_WASM}; using default contract ID: ${CONTRACT_ID}" >&2
else
  log "No deployment key provided; using default contract ID: ${CONTRACT_ID}"
fi

if [ -w "${ENV_FILE}" ]; then
  if grep -q "^CONTRACT_ID=" "${ENV_FILE}" 2>/dev/null; then
    sed -i "s/^CONTRACT_ID=.*/CONTRACT_ID=${CONTRACT_ID}/" "${ENV_FILE}"
  else
    printf 'CONTRACT_ID=%s\n' "${CONTRACT_ID}" >> "${ENV_FILE}"
  fi
  log "Wrote CONTRACT_ID=${CONTRACT_ID} to ${ENV_FILE}"
else
  log "Cannot write to ${ENV_FILE}; exported CONTRACT_ID=${CONTRACT_ID}"
  export CONTRACT_ID
fi

echo "CONTRACT_ID=${CONTRACT_ID}"
